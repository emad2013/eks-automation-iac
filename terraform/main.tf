provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

data "aws_availability_zones" "azs" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name = var.name
  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.azs.names
  private_subnets = var.private_subnet_cidr_blocks
  public_subnets  = var.public_subnet_cidr_blocks

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.name
  }

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                   = var.name
  kubernetes_version     = var.k8s_version
  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    external_admin = {
      principal_arn     = aws_iam_role.external-admin.arn
      kubernetes_groups = ["none"]
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    external_developer = {
      principal_arn     = aws_iam_role.external-developer.arn
      kubernetes_groups = ["none"]
      policy_associations = {
        developer = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = {
            type       = "namespace"
            namespaces = ["online-boutique"]
          }
        }
      }
    }
  }

  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    initial = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 2
    }
  }

  tags = var.tags
}

# ── Stage 1: Install AWS LBC + metrics-server ONLY ───────────────────────────
# Karpenter is intentionally excluded here — it must wait until the LBC
# webhook is fully healthy, otherwise Service creation is intercepted by a
# webhook with no backing pod and the apply fails.
module "eks_blueprints_addons_lbc" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_karpenter                    = false   # ← installed separately below

  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "region"
        value = var.aws_region
      }
    ]
  }

  depends_on = [module.eks]

  tags = var.tags
}

# ── Stage 2: Wait for LBC webhook to become ready ────────────────────────────
# The mutating webhook "mservice.elbv2.k8s.aws" is only healthy once the
# aws-load-balancer-controller Deployment has at least one Ready pod.
# Without this gate, Karpenter's Helm chart creates a Service that hits the
# webhook before it has endpoints → "no endpoints available" error.
resource "null_resource" "wait_for_lbc" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}
      kubectl rollout status deployment/aws-load-balancer-controller \
        -n kube-system --timeout=300s
    EOT
    interpreter = ["bash", "-c"]
  }

  depends_on = [module.eks_blueprints_addons_lbc]
}

# ── Stage 3: Install Karpenter AFTER webhook is healthy ──────────────────────
module "eks_blueprints_addons_karpenter" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = false
  enable_metrics_server               = false
  enable_karpenter                    = true

  depends_on = [null_resource.wait_for_lbc]   # ← guaranteed LBC webhook is up

  tags = var.tags
}

# ── Flux bootstrap ────────────────────────────────────────────────────────────
provider "flux" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
  git = {
    url = "https://github.com/${var.github_org}/${var.github_repo}.git"
    http = {
      username = "git"
      password = var.github_token
    }
  }
}

resource "flux_bootstrap_git" "this" {
  path               = "clusters/dev/${var.name}"
  embedded_manifests = true
  components_extra   = ["image-reflector-controller", "image-automation-controller"]

  # Fix: give Flux more time to reconcile on first bootstrap
  # Default is too short when Karpenter + monitoring are also starting
  kustomization_override = {
    spec = {
      timeout      = "10m"
      retryInterval = "2m"
    }
  }

  depends_on = [module.eks_blueprints_addons_karpenter]
}
