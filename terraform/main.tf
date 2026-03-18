provider "aws" {
  region = var.aws_region
}
# Added alias to access karpenter repo in us-east-1
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}
#-----------------Helm access to cluster----------------------
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
# Passing token to us-east-1 for karpenter ecr
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}
#----------------VPC module to create VPC, subnets, networking stack,ALB, natgateway for egres traffic from worker nodes--------------------- 
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
#---------------------------EKS modue to install and setup eks cluster auto policy assingment and dependencies.-------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                   = var.name
  kubernetes_version     = var.k8s_version
  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true
#--------- Deprecated aws-configmap to map users IAM OIDC , latest providers access_entries allow mapping roles from IAM to kubenetes"
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

#--------------IAM policy EBS Version 6.0 ----------------------------------------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name                  = "ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    this = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

#------------ EKS Addons — includes EBS CSI Driver with IRSA-----------------------
 addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
#------------AWS native CNI pod networking-----------------------------------------
     
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}

  }
#----------------- Worker Node groups-------------------------
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

#-------------------- Stage 1: LBC + metrics-server only--------------------------------
# EKS community based bluprint addons module to implements addons
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_karpenter                    = false

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
  tags       = var.tags
}

# Stage 2: Wait for LBC webhook to be ready
#--------------Avoid race condition during setup for aws load balancer endpoints------------------------
resource "null_resource" "wait_for_lbc" {
  provisioner "local-exec" {
    command     = <<-EOT
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}
      kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s
    EOT
    interpreter = ["bash", "-c"]
  }
  depends_on = [module.eks_blueprints_addons]
}

# Stage 3: Karpenter after LBC webhook is healthy
module "eks_blueprints_addons_karpenter" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller        = false
  enable_metrics_server                      = false
  enable_karpenter                           = true
  karpenter_enable_spot_termination          = true
  karpenter_enable_instance_profile_creation = true
# karpenter version to deploy from addon on repo.
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    chart_version       = "0.37.0"
  }

  depends_on = [null_resource.wait_for_lbc]
  tags       = var.tags
}

#----------------Karpenter role to trigger nodes during node autoscaling---------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons_karpenter.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
  depends_on    = [module.eks_blueprints_addons_karpenter]
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
#---------------- Flux boottrap to integrate with  eks--------------------------------------
resource "flux_bootstrap_git" "this" {
  path               = "clusters/dev/${var.name}"
  embedded_manifests = true
  components_extra   = ["image-reflector-controller", "image-automation-controller"]
  depends_on         = [module.eks_blueprints_addons_karpenter]
}
