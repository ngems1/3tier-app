# One-time account setup, applied by an administrator (not by CI):
#
#   * GitHub OIDC identity provider, so GitHub Actions never needs AWS keys
#   * separate IAM roles for each pipeline stage:
#       - plan    : read-only, used by pull-request plans
#       - build   : bakes release AMIs with Packer and publishes artifacts (main only)
#       - deploy-<env> : applies Terraform, only from the matching GitHub Environment
#   * a versioned, encrypted bucket for release artifacts
#   * ECR repositories for the frontend and backend container images
#     (immutable SHA tags, scan on push, lifecycle cleanup)
#
# The Terraform state bucket is created before this, by ../state-bucket.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  oidc_arn   = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  # GitHub identifies the repository either by name (owner/repo) or by name and
  # numeric IDs (owner@id/repo@id); accept both.
  repo_subs = compact(["repo:${var.github_repository}", var.github_repository_with_ids == "" ? "" : "repo:${var.github_repository_with_ids}"])
  state_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  iam_name  = var.project
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# Trust policy helper: only tokens for this repository with the given
# subject (branch, pull request or GitHub Environment) can assume a role.
data "aws_iam_policy_document" "trust" {
  for_each = merge(
    {
      plan  = flatten([for r in local.repo_subs : ["${r}:pull_request", "${r}:ref:refs/heads/main"]])
      build = flatten([for r in local.repo_subs : ["${r}:ref:refs/heads/main", "${r}:environment:build"]])
    },
    { for env in var.environments : "deploy-${env}" => [for r in local.repo_subs : "${r}:environment:${env}"] },
  )

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Release artifact bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  #checkov:skip=CKV_AWS_18:Access logging for the artifact bucket is not required in this project.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required; AMIs are the deployable unit.
  #checkov:skip=CKV2_AWS_62:No consumers need event notifications.
  bucket = "${var.project}-artifacts-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "cleanup"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# ECR repositories (container images, tagged with the git commit SHA)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  #checkov:skip=CKV_AWS_136:Encrypted with the AWS managed KMS key for ECR so every pipeline role can pull without extra key grants.
  for_each             = toset(var.container_images)
  name                 = "${var.project}-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent ${var.images_to_keep} release images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.images_to_keep
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

# PLAN: read-only. Pull-request plans run with -lock=false, so no write access
# to state is needed.
resource "aws_iam_role" "plan" {
  name                 = "${local.iam_name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# BUILD: bake AMIs with Packer and upload release artifacts.
data "aws_iam_policy_document" "build" {
  #checkov:skip=CKV_AWS_111:Packer creates temporary instances, volumes, key pairs and security groups whose IDs are unknown until build time.
  #checkov:skip=CKV_AWS_356:See CKV_AWS_111; EC2 create/describe actions for Packer cannot be scoped to ARNs in advance. ECR and S3 access is scoped to the project repositories and bucket.
  #checkov:skip=CKV_AWS_109:Packer sets AMI and snapshot attributes on the images it creates; images are not shared outside the account.
  #checkov:skip=CKV_AWS_107:ecr:GetAuthorizationToken is required for docker login to push release images; it has no resource-level scoping.
  statement {
    sid = "PackerEc2"
    actions = [
      "ec2:AttachVolume", "ec2:AuthorizeSecurityGroupIngress", "ec2:CopyImage", "ec2:CreateImage",
      "ec2:CreateKeyPair", "ec2:CreateSecurityGroup", "ec2:CreateSnapshot", "ec2:CreateTags",
      "ec2:CreateVolume", "ec2:DeleteKeyPair", "ec2:DeleteSecurityGroup", "ec2:DeleteSnapshot",
      "ec2:DeleteVolume", "ec2:DeregisterImage", "ec2:Describe*", "ec2:DetachVolume",
      "ec2:ModifyImageAttribute", "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute", "ec2:RegisterImage", "ec2:RunInstances", "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PublishArtifacts"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAndScanImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
}

resource "aws_iam_policy" "build" {
  #checkov:skip=CKV_AWS_290:Packer must create and clean up temporary instances, volumes and security groups whose IDs are not known in advance.
  #checkov:skip=CKV_AWS_355:See CKV_AWS_290; EC2 describe/create actions do not support resource-level scoping at build time.
  #checkov:skip=CKV_AWS_289:See CKV_AWS_290.
  name   = "${local.iam_name}-github-build"
  policy = data.aws_iam_policy_document.build.json
}

resource "aws_iam_role" "build" {
  name                 = "${local.iam_name}-github-build"
  assume_role_policy   = data.aws_iam_policy_document.trust["build"].json
  max_session_duration = 7200
}

resource "aws_iam_role_policy_attachment" "build" {
  role       = aws_iam_role.build.name
  policy_arn = aws_iam_policy.build.arn
}

# DEPLOY: applies Terraform for one environment, on EC2 (Project 1) or ECS
# (Project 2). Service access is limited to what the stacks use; IAM changes
# are limited to this project's own roles.
data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_111:Terraform creates resources whose ARNs are not known in advance across these services; IAM writes are restricted to project-prefixed names.
  #checkov:skip=CKV_AWS_356:See CKV_AWS_111.
  #checkov:skip=CKV_AWS_109:IAM permissions management is limited to roles, policies and instance profiles named with the project prefix.
  #checkov:skip=CKV_AWS_107:The deploy role manages the RDS-managed database secret (Secrets Manager) and passes only project roles.
  #checkov:skip=CKV_AWS_108:The deploy role reads Terraform state and project resources to plan changes; access is limited to this account and the project buckets.
  statement {
    sid = "ManageStackServices"
    actions = [
      "acm:*", "application-autoscaling:*", "autoscaling:*", "cloudwatch:*", "ec2:*",
      "ecs:*", "elasticloadbalancing:*", "kms:*", "logs:*", "rds:*", "route53:*",
      "secretsmanager:*", "sns:*", "ssm:*", "wafv2:*",
    ]
    resources = ["*"]
  }

  # ECS task definitions are pinned to the digest of the release's images.
  statement {
    sid       = "ReadReleaseImages"
    actions   = ["ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListTagsForResource"]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }

  statement {
    sid     = "ManageProjectBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::${var.project}-*",
      "arn:${local.partition}:s3:::${var.project}-*/*",
    ]
  }

  statement {
    sid       = "TerraformState"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_arn, "${local.state_arn}/*"]
  }

  statement {
    sid = "ManageProjectIam"
    actions = [
      "iam:*Role",
      "iam:*RolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
      "iam:*Policy",
      "iam:*PolicyVersion",
      "iam:ListPolicyVersions",
      "iam:*InstanceProfile",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }
}

resource "aws_iam_policy" "deploy" {
  #checkov:skip=CKV_AWS_290:Terraform creates resources whose ARNs are not known in advance across these services; IAM itself is restricted to project-prefixed names.
  #checkov:skip=CKV_AWS_355:See CKV_AWS_290.
  #checkov:skip=CKV_AWS_289:See CKV_AWS_290.
  #checkov:skip=CKV_AWS_286:iam:PassRole is limited to this project's own roles.
  #checkov:skip=CKV_AWS_287:Credential exposure actions (secretsmanager) are needed for the RDS-managed secret.
  #checkov:skip=CKV_AWS_288:See CKV_AWS_290.
  #checkov:skip=CKV2_AWS_40:Full IAM privileges are not granted; IAM writes are restricted to project-prefixed resources.
  name   = "${local.iam_name}-github-deploy"
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role" "deploy" {
  for_each             = toset(var.environments)
  name                 = "${local.iam_name}-github-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.trust["deploy-${each.key}"].json
  max_session_duration = 7200
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = toset(var.environments)
  role       = aws_iam_role.deploy[each.key].name
  policy_arn = aws_iam_policy.deploy.arn
}
