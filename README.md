# eks-automation-iac
eks-automation-iac terraform
eks-automation-iac
Terraform IaC for provisioning and managing an Amazon EKS cluster on AWS with full GitOps support via FluxCD.

What This Deploys

VPC — 3 private + 3 public subnets across all AZs with NAT Gateway
EKS Cluster — Kubernetes 1.33 with managed node groups
IAM Roles — Least-privilege roles for admin and developer access via sts:AssumeRole
EKS Access Entries — Fine-grained Kubernetes RBAC via AWS access entries API
Kubernetes RBAC — Namespace and cluster-scoped roles and bindings
EKS Blueprints Addons:

AWS Load Balancer Controller
Metrics Server
Karpenter


FluxCD — GitOps bootstrap pointing to gitops-flux repository

==================================================================================================================
Repository Structure
eks-automation-iac/
│
├── .gitignore
├── README.md
│
└── terraform/
    ├── backend.tf                # Local state config
    ├── versions.tf               # Provider version constraints
    ├── main.tf                   # VPC, EKS, addons, FluxCD
    ├── iam_role.tf               # IAM roles and policies
    ├── kubernetes_resources.tf   # Namespaces, roles, rolebindings
    ├── variables.tf              # All input variables
    ├── outputs.tf                # Cluster outputs
    └── terraform.tfvars          # ← NOT committed, see .gitignore
===================================================================================================================
Provider Versions
Provider   Version                   Notes   
hashicorp/aws>= 6.0
hashicorp/kubernetes>= 2.20 
hashicorp/helm>= 2.9, < 3.0v3       not supported by eks-blueprints-addons
fluxcd/flux~> 1.4                   Note: NOT hashicorp/flux

===================================================================================================================
Module                          Versions
terraform-aws-modules/eks/aws~> 21.0
terraform-aws-modules/vpc/aws~> 6.6.0
aws-ia/eks-blueprints-addons/aws~> 1.0
===================================================================================================================
IAM role and EKS RBAC Mapping
IAM User
    │
    │  sts:AssumeRole
    ▼
IAM Role (external-admin or external-developer)
    │
    │  eks:DescribeCluster
    ▼
EKS Cluster
    │
    │  EKS Access Entry (RBAC policy)
    ▼
Kubernetes Resources

==================================================================================================================== 