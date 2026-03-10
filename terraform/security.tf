# security.tf
# Adds Pod Security Admission labels to namespaces and a default-deny
# NetworkPolicy to online-boutique — replaces deprecated PodSecurityPolicy.

# ── Pod Security Admission ─────────────────────────────────────────────────
# Labels on the namespace tell the K8s admission controller to enforce
# the "baseline" profile (blocks privileged containers, host networking etc.)
# and warn/audit on anything that violates "restricted" (stricter).

resource "kubernetes_labels" "online_boutique_psa" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = kubernetes_namespace_v1.online-boutique.metadata[0].name
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "baseline"
    "pod-security.kubernetes.io/warn"    = "restricted"
    "pod-security.kubernetes.io/audit"   = "restricted"
  }
  depends_on = [kubernetes_namespace_v1.online-boutique]
}

resource "kubernetes_labels" "flux_system_psa" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "flux-system"
  }
  labels = {
    # Flux controllers need privileged access — baseline is the safe minimum
    "pod-security.kubernetes.io/enforce" = "baseline"
    "pod-security.kubernetes.io/warn"    = "baseline"
    "pod-security.kubernetes.io/audit"   = "baseline"
  }
  depends_on = [module.eks_blueprints_addons_karpenter]
}

# ── NetworkPolicy — default deny all in online-boutique ───────────────────
# Block all ingress and egress by default. Specific policies in the app
# manifests (committed to git) then open only what is needed.

resource "kubernetes_network_policy_v1" "online_boutique_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.online-boutique.metadata[0].name
  }

  spec {
    pod_selector {} # applies to ALL pods in namespace

    policy_types = ["Ingress", "Egress"]

    # Allow DNS egress so pods can resolve service names
    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.online-boutique]
}

# ── NetworkPolicy — allow monitoring scraping from monitoring namespace ────
resource "kubernetes_network_policy_v1" "online_boutique_allow_prometheus" {
  metadata {
    name      = "allow-prometheus-scrape"
    namespace = kubernetes_namespace_v1.online-boutique.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.online-boutique]
}
