# iam_role.tf
# NOTE: locals block removed — aws_k8s_role_mapping no longer needed.
# access_entries in eks.tf now references these roles directly.
#
# NOTE: inline_policy is deprecated in aws provider >= 5.68 / v6.
# Replaced with separate aws_iam_role_policy resources.

# ──────────────────────────────────────────────
# Admin Role
# ──────────────────────────────────────────────
resource "aws_iam_role" "external-admin" {
  name = "external-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = var.user_for_admin_role
        }
      }
    ]
  })
}

# Karpenter Controller — extra IAM permissions
# ──────────────────────────────────────────────
# eks_blueprints_addons creates the Karpenter controller role automatically,
# but it does NOT attach iam:PassRole or instance profile permissions.
# Without these, EC2NodeClass reconciliation fails with AccessDenied (403).

data "aws_iam_role" "karpenter_controller" {
  name       = "karpenter-${module.eks.cluster_name}"
  depends_on = [module.eks_blueprints_addons_karpenter]
}

# iam-karpenter.tf

# Fix: use aws_iam_roles (plural) with regex to find the actual role name
# eks_blueprints_addons may name it differently depending on version
data "aws_iam_roles" "karpenter" {
  name_regex = ".*karpenter.*"
  depends_on = [module.eks_blueprints_addons_karpenter]
}

locals {
  # Filter to find the role scoped to this cluster
  karpenter_role_name = [
    for name in tolist(data.aws_iam_roles.karpenter.names) :
    name if can(regex(module.eks.cluster_name, name))
  ][0]
}

resource "aws_iam_role_policy" "karpenter_pass_role" {
  name = "karpenter-pass-role"
  role = local.karpenter_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "KarpenterPassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-${module.eks.cluster_name}"
      },
      {
        Sid    = "KarpenterInstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      }
    ]
  })

  depends_on = [module.eks_blueprints_addons_karpenter]
}

data "aws_caller_identity" "current" {}

# Needed to resolve account ID for ARN construction
data "aws_caller_identity" "current" {}


resource "aws_iam_role_policy" "external-admin-policy" {
  name = "external-admin-policy"
  role = aws_iam_role.external-admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["eks:DescribeCluster"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Developer Role
# ──────────────────────────────────────────────
resource "aws_iam_role" "external-developer" {
  name = "external-developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = var.user_for_dev_role
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "external-developer-policy" {
  name = "external-developer-policy"
  role = aws_iam_role.external-developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["eks:DescribeCluster"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
