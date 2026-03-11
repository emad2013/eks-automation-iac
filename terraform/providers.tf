##  Providers that require to implement EKS Cluster and dependencies based on usecase.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9, < 3.0"   # blueprints-addons requires helm v2.x, NOT v3
    }
    flux = {
      source  = "fluxcd/flux"      # ← must be fluxcd/flux NOT hashicorp/flux
      version = "~> 1.4"
    }
  }
}

