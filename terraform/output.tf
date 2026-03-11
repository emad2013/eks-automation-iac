# ── Cluster Info ──────────────────────────────────────────────────
# EKS cluster name
output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

# EKS endpoint 
output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}
# Cluster Version
output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of CREATING, ACTIVE, DELETING, FAILED"
  value       = module.eks.cluster_status
}

# ── Kubectl Configuration ─────────────────────────────────────────
 ## terraform apply completion print output to get updated kubeconfig for access
output "configure_kubectl" {
  description = "Run this command to update your kubeconfig after apply"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ── Extra outputs ─────────────────────────────────────────────────
## To access cluster access in kubernetes_resources to deploy EKS kubernetes resources inside kubernetes.
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — required by eks-blueprints-addons"
  value       = module.eks.oidc_provider_arn
}
