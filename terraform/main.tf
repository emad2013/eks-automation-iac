
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

  # Grants the IAM identity running terraform apply full admin access
  enable_cluster_creator_admin_permissions = true

  access_entries = {

  # --- Admin Role ---
  # AmazonEKSClusterAdminPolicy → AmazonEKSViewPolicy
  # cluster-wide but READ ONLY (get, list, watch)
  external_admin = {
    principal_arn     = aws_iam_role.external-admin.arn
    kubernetes_groups = ["none"]
    policy_associations = {
      admin = {
        # ❌ BEFORE: AmazonEKSClusterAdminPolicy  ← full cluster admin
        # ✅ AFTER:  AmazonEKSViewPolicy           ← read only cluster-wide
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }

  # --- Developer Role ---
  # AmazonEKSEditPolicy cluster-wide → AmazonEKSViewPolicy namespace-scoped
  external_developer = {
    principal_arn     = aws_iam_role.external-developer.arn
    kubernetes_groups = ["none"]
    policy_associations = {
      developer = {
        # ❌ BEFORE: AmazonEKSEditPolicy  type = "cluster" ← edit rights everywhere
        # ✅ AFTER:  AmazonEKSEditPolicy  type = "namespace" ← edit only in online-boutique
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
        access_scope = {
          type       = "namespace"
          namespaces = ["online-boutique"]  # ← scoped to one namespace only
        }
      }
    }
  }
}

  addons = {
    vpc-cni = {
      before_compute = true   # ← THIS was the missing fix
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    initial = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
    }
  }

  tags = var.tags
}

# eks_blueprints_addons must wait for node group to be healthy
# before trying to install helm charts
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_karpenter                    = true
 
  # LB metadata pass VPC ID explicitly so LBC doesn't rely on EC2 metadata
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
  # Explicit dependency — ensures node group is ACTIVE before helm charts install
  depends_on = [module.eks]

  tags = var.tags
}

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
  path       = "clusters/${var.name}"
  embedded_manifests = true
  depends_on = [module.eks_blueprints_addons]
}
