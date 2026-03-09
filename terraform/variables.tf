variable aws_region {
  default = "eu-west-1"
}

variable name {
    default = "myapp-eks"
}

variable k8s_version {
    default = "1.33"
}

variable vpc_cidr_block {
    default = "10.0.0.0/16"
}
variable private_subnet_cidr_blocks {
    default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
variable public_subnet_cidr_blocks {
    default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable tags {
    default = {
        App  = "eks-secops"
    }
}
# variables.tf — add these for FluxCD
variable "github_org" {
  description = "GitHub organisation or username that owns the GitOps repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for FluxCD GitOps"
  type        = string
}

variable "github_token" {
  description = "GitHub Personal Access Token for FluxCD bootstrap"
  type        = string
  sensitive   = true
}
variable user_for_admin_role {}
variable user_for_dev_role {}