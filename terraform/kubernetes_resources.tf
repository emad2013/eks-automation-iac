provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

resource "kubernetes_namespace_v1" "online-boutique" {
  metadata {
    name = "online-boutique"
  }

  # Wait for ALL addons (including Karpenter) to be ready
  depends_on = [module.eks_blueprints_addons_karpenter]
}

resource "kubernetes_role_v1" "namespace-viewer" {
  metadata {
    name      = "namespace-viewer"
    namespace = "online-boutique"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [kubernetes_namespace_v1.online-boutique]
}

resource "kubernetes_role_binding_v1" "namespace-viewer" {
  metadata {
    name      = "namespace-viewer"
    namespace = "online-boutique"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "namespace-viewer"
  }

  subject {
    kind      = "User"
    name      = "developer"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [kubernetes_role_v1.namespace-viewer]
}

resource "kubernetes_cluster_role_v1" "cluster_viewer" {
  metadata {
    name = "cluster-viewer"
  }

  rule {
    api_groups = [""]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [module.eks_blueprints_addons_karpenter]
}

resource "kubernetes_cluster_role_binding_v1" "cluster_viewer" {
  metadata {
    name = "cluster-viewer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-viewer"
  }

  subject {
    kind      = "User"
    name      = "admin"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [kubernetes_cluster_role_v1.cluster_viewer]
}
