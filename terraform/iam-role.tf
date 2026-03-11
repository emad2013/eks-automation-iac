# iam_role.tf

# ──────────────────────────────────────────────
# Admin Role sts Assume for IAM
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
# Developer Role sts Assume for IAM
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
