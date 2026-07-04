# Fix for F-11 / F-12 - replaces two wildcard IAM policies
# (aws_iam_user_policy.userpolicy in iam.tf, aws_iam_role_policy.ec2policy in db-app.tf)
# with the tag-scoped model designed in 03-identity-governance/cross-cloud-iam-design.md.
#
# The standing IAM user + static access key (aws_iam_user.user, aws_iam_access_key.user)
# is removed entirely, not just re-scoped - CI authenticates via the OIDC-federated role
# below instead. See remediation-advisory.md Advisory 3 for the cutover sequence.

# --- OIDC federation trust (replaces the static IAM user + access key) ---

resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.example-gov-programme.internal"
  client_id_list  = ["https://gitlab.example-gov-programme.internal"]
  thumbprint_list = [] # populated from the GitLab instance's TLS cert thumbprint at apply time
}

resource "aws_iam_role" "ci_pipeline" {
  name = "${local.resource_prefix.value}-ci-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.gitlab.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "gitlab.example-gov-programme.internal:sub" = "project_path:programme/web-app-db:ref_type:branch:ref:main"
        }
      }
    }]
  })

  tags = {
    workload-id = "web-app-db"
  }
}

# --- Scoped policy: replaces both wildcard policies with tag-conditioned, action-limited access ---

resource "aws_iam_role_policy" "ci_pipeline_scoped" {
  name = "${local.resource_prefix.value}-ci-scoped-policy"
  role = aws_iam_role.ci_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformStateAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::tf-state-web-app-db",
          "arn:aws:s3:::tf-state-web-app-db/*"
        ]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:*:*:table/tf-lock-web-app-db"
      },
      {
        Sid      = "ManageOnlyThisWorkloadsResources"
        Effect   = "Allow"
        Action   = [
          "ec2:Describe*",
          "rds:Describe*",
          "rds:ModifyDBInstance",
          "s3:GetBucket*",
          "s3:PutBucket*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/workload-id" = "web-app-db" }
        }
      }
    ]
  })
}

# aws_iam_user.user, aws_iam_access_key.user, aws_iam_user_policy.userpolicy (iam.tf),
# and aws_iam_role_policy.ec2policy (db-app.tf) are removed by this change - deliberately
# not shown as "commented out" in this file; they are deleted from the source files they
# came from as part of applying this fix, per the repository's commit hygiene policy of not
# leaving dead/commented-out resource blocks in the codebase.
