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

resource "aws_iam_role_policy" "karpenter_pass_role" {
  name = "karpenter-pass-role"
  role = data.aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Required for EC2NodeClass to attach the node role to instance profiles
        Sid    = "KarpenterPassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-${module.eks.cluster_name}"
      },
      {
        # Required for Karpenter to create/manage EC2 instance profiles
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
}

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
