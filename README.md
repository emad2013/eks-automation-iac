# eks-automation-iac

Terraform IaC for provisioning and managing a production-ready Amazon EKS cluster on AWS with full GitOps support via FluxCD.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Account                                │
│                                                                     │
│  ┌──────────────────────── VPC (10.0.0.0/16) ───────────────────┐  │
│  │                                                               │  │
│  │   Public Subnets (3 AZs)          Private Subnets (3 AZs)    │  │
│  │   ┌─────────────────┐             ┌─────────────────────┐    │  │
│  │   │ 10.0.101.0/24   │             │ 10.0.1.0/24         │    │  │
│  │   │ 10.0.102.0/24   │   NAT GW   │ 10.0.2.0/24         │    │  │
│  │   │ 10.0.103.0/24   │──────────►  │ 10.0.3.0/24         │    │  │
│  │   │                 │             │                     │    │  │
│  │   │  ALB (public)   │             │  EKS Control Plane  │    │  │
│  │   └─────────────────┘             │  Managed Nodes (t3) │    │  │
│  │                                   │  Karpenter Nodes    │    │  │
│  │                                   └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────┐     │
│  │ IAM Roles   │    │ EKS Access   │    │ Karpenter IAM      │     │
│  │ admin       │───►│ Entries      │───►│ Controller + Node   │     │
│  │ developer   │    │ RBAC Mapping │    │ Roles               │     │
│  └─────────────┘    └──────────────┘    └────────────────────┘     │
│                                                                     │
│  ┌──────────────────────── EKS Addons (Staged) ─────────────────┐  │
│  │  AWS LBC + Metrics Server ──► Karpenter ──► FluxCD           │  │
│  │  (Stage 1)                    (Stage 3)     (Stage 4)        │  │
│  │                 wait_for_lbc                                  │  │
│  │                 (Stage 2)                                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  FluxCD ──── syncs from ────► github.com/emad2013/gitops-fluxcd    │
└─────────────────────────────────────────────────────────────────────┘
```
## What This Deploys

| Component | Details |
|-----------|---------|
| **VPC** | 3 private + 3 public subnets across all AZs, single NAT Gateway |
| **EKS Cluster** | Kubernetes 1.33, managed node group (t3.medium, 1–2 nodes) |
| **EKS Addons** | vpc-cni, kube-proxy, coredns |
| **IAM Roles** | Least-privilege `external-admin` and `external-developer` via `sts:AssumeRole` |
| **EKS Access Entries** | admin → cluster-wide ViewPolicy, developer → namespace-scoped EditPolicy |
| **Kubernetes RBAC** | `cluster-viewer` ClusterRole, `namespace-viewer` Role in `online-boutique` |
| **AWS Load Balancer Controller** | Ingress and Service type LoadBalancer support |
| **Metrics Server** | Required for HPA (Horizontal Pod Autoscaler) |
| **Karpenter** | Node autoscaling with spot termination handling and instance profile creation |
| **FluxCD** | GitOps bootstrap with image-reflector and image-automation controllers |

## Repository Structure

```
eks-automation-iac/
├── .gitignore
├── README.md
└── terraform/
    ├── backend.tf                  # State config (local)
    ├── iam-role.tf                 # IAM roles (admin, developer) + inline policies
    ├── kubernetes_resources.tf     # Kubernetes provider, namespaces, Roles, RoleBindings, outputs
    ├── main.tf                     # VPC, EKS, addons (staged), Karpenter, Flux bootstrap
    ├── output.tf                   # Cluster outputs (endpoint, kubeconfig command)
    ├── providers.tf                # Provider version constraints (aws, kubernetes, helm, flux)
    ├── variables.tf                # All input variables
    └── terraform.tfvars            # ← NOT committed (secrets), see .gitignore
```

### File Descriptions

| File | What It Does |
|------|-------------|
| `backend.tf` | Configures Terraform state backend (local) |
| `iam-role.tf` | Creates `external-admin` and `external-developer` IAM roles with `sts:AssumeRole` trust policies and `eks:DescribeCluster` permissions |
| `kubernetes_resources.tf` | Configures the Kubernetes provider, creates `online-boutique` namespace, `namespace-viewer` Role + RoleBinding (developer), `cluster-viewer` ClusterRole + ClusterRoleBinding (admin) |
| `main.tf` | Core infrastructure — VPC, EKS, eks-blueprints-addons (LBC + Metrics Server), LBC webhook wait gate, Karpenter addon, Karpenter node access entry, Flux provider + bootstrap |
| `output.tf` | Exports cluster name, endpoint, platform version, status, kubeconfig command, CA data, OIDC ARN |
| `providers.tf` | Version constraints for aws (>= 6.0), kubernetes (>= 2.20), helm (>= 2.9 < 3.0), flux (~> 1.4) |
| `variables.tf` | Input variables — region, cluster name, k8s version, VPC CIDRs, subnets, tags, GitHub org/repo/token, IAM user ARNs |

## Provider & Module Versions

| Provider | Version | Notes |
|----------|---------|-------|
| `hashicorp/aws` | >= 6.0 | Also uses `aws.virginia` alias for ECR public token |
| `hashicorp/kubernetes` | >= 2.20 | |
| `hashicorp/helm` | >= 2.9, < 3.0 | v3 not supported by eks-blueprints-addons |
| `fluxcd/flux` | ~> 1.4 | Must be `fluxcd/flux`, NOT `hashicorp/flux` |

| Module | Version |
|--------|---------|
| `terraform-aws-modules/eks/aws` | ~> 21.0 |
| `terraform-aws-modules/vpc/aws` | ~> 6.6.0 |
| `aws-ia/eks-blueprints-addons/aws` | ~> 1.0 (used twice — LBC stage and Karpenter stage) |

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5
- `kubectl` installed
- A GitHub Personal Access Token (PAT) with `repo` scope
- The [gitops-fluxcd](https://github.com/emad2013/gitops-fluxcd) repo created for Flux manifests

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/emad2013/eks-automation-iac.git
cd eks-automation-iac/terraform
```

### 2. Create `terraform.tfvars`

```hcl
github_org          = "emad2013"
github_repo         = "gitops-fluxcd"
github_token        = ""
user_for_admin_role = ""
user_for_dev_role   = ""
```

Fill in your GitHub PAT and the IAM user ARNs that should assume the admin and developer roles.

### 3. Initialize and deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes ~15–20 minutes. The staged approach ensures addons install in the correct order:

1. **Stage 1** — EKS cluster + VPC + AWS LBC + Metrics Server
2. **Stage 2** — `null_resource.wait_for_lbc` waits for LBC webhook to have healthy endpoints
3. **Stage 3** — Karpenter installs after LBC webhook is ready + Karpenter node access entry created
4. **Stage 4** — FluxCD bootstraps after all addons are healthy

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name myapp-eks --region eu-west-1
```

### 5. Verify

```bash
# Cluster
kubectl get nodes

# Addons
kubectl get pods -n kube-system

# Karpenter
kubectl get ec2nodeclass
kubectl get nodepool

# Flux
flux get kustomizations
flux get sources git
```

## IAM → Kubernetes RBAC Flow

```
IAM User
    │  sts:AssumeRole
    ▼
IAM Role (external-admin / external-developer)
    │  eks:DescribeCluster
    ▼
EKS Access Entry (AWS-native RBAC)
    │  AmazonEKSViewPolicy (admin, cluster-wide)
    │  AmazonEKSEditPolicy (developer, online-boutique namespace)
    ▼
Kubernetes RBAC
    ├── admin     → cluster-viewer ClusterRole (get/list/watch all resources)
    └── developer → namespace-viewer Role (get/list/watch pods, services, deployments in online-boutique)
```

## Staged Addon Deployment

```
module.eks
    │
    ▼
module.eks_blueprints_addons (LBC + Metrics Server)
    │
    ▼
null_resource.wait_for_lbc (kubectl rollout status)
    │
    ▼
module.eks_blueprints_addons_karpenter (Karpenter + spot termination + instance profile)
    │
    ▼
aws_eks_access_entry.karpenter_nodes (EC2_LINUX access for Karpenter nodes)
    │
    ▼
flux_bootstrap_git.this (FluxCD with image automation controllers)
```

**Why staged?** The AWS LBC installs a mutating webhook (`mservice.elbv2.k8s.aws`). If Karpenter's Helm chart creates a Service before the webhook has endpoints, the apply fails with "no endpoints available". The `wait_for_lbc` null resource gates Karpenter until the webhook is healthy.

## Troubleshooting

### EC2NodeClass stuck in `InProgress` — "Failed to resolve instance profile"

**Cause:** The `role` field in EC2NodeClass (in the gitops-fluxcd repo) didn't match the actual IAM role name created by Terraform. Terraform generates role names with timestamp suffixes (e.g., `karpenter-myapp-eks-20260310084212316800000018`), but the manifest referenced a different name.

**Fix:** Get the correct role name and update the EC2NodeClass manifest in your Flux repo:
```bash
aws iam list-roles --query 'Roles[?contains(RoleName,`karpenter-myapp-eks`)].RoleName'
```

### EC2NodeClass `spec.role` is immutable

**Cause:** Karpenter does not allow changing the `role` field on an existing EC2NodeClass via patch.

**Fix:** Delete and let Flux recreate it:
```bash
flux suspend kustomization flux-system
kubectl delete ec2nodeclass default
# Push corrected role name to git
flux resume kustomization flux-system
```

### Missing `AmazonSSMManagedInstanceCore` on Karpenter node role

**Cause:** The Karpenter node role had only 3 of the 4 required policies. SSM is needed for node bootstrapping.

**Fix:**
```bash
aws iam attach-role-policy \
  --role-name karpenter-myapp-eks-<SUFFIX> \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### Flux bootstrap timeout — Kustomization not ready

**Cause:** Flux health checks waited on Karpenter EC2NodeClass which was failing due to IAM/role issues above. The chain: EC2NodeClass not ready → Flux Kustomization not ready → bootstrap timeout.

**Fix:** Resolve the underlying Karpenter issues first. If needed, re-run `terraform apply` after fixing.

### LBC webhook — "no endpoints available" during Karpenter install

**Cause:** Karpenter's Helm chart tried to create a Service before the LBC webhook pod was running.

**Fix:** Already handled in the code — `null_resource.wait_for_lbc` runs `kubectl rollout status` on the LBC deployment before Karpenter stage begins.

### Kustomize path error — `../base: no such file or directory`

**Cause:** In the Flux repo, an overlay `kustomization.yaml` used `../base` but from `overlays/dev/` the correct relative path is `../../base`.

**Fix:** Change `resources: [../base]` to `resources: [../../base]` in the overlay.

## Cleanup

```bash
cd terraform
terraform destroy
```

> **Note:** If Karpenter has provisioned nodes, they will be terminated during destroy. If destroy hangs, manually delete any `nodeclaim` resources first:
> ```bash
> kubectl delete nodeclaim --all
> ```

## Related Repositories

| Repo | Purpose |
|------|---------|
| [gitops-fluxcd](https://github.com/emad2013/gitops-fluxcd) | Flux GitOps manifests — Karpenter configs, app deployments, monitoring stack |
