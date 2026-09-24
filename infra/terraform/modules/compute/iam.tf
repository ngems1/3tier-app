# Runtime roles, one per tier (separate from the CI deployment roles created
# in infra/terraform/bootstrap). Both tiers get SSM Session Manager access
# (no SSH keys) and a CloudWatch Agent policy scoped to this environment's
# log groups. Only the app tier can read the database secret.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition      = data.aws_partition.current.partition
  region         = data.aws_region.current.region
  account_id     = data.aws_caller_identity.current.account_id
  log_group_arns = [for g in var.log_group_names : "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${g}"]
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudwatch_agent" {
  statement {
    sid       = "PutMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metrics_namespace]
    }
  }

  statement {
    sid       = "DescribeForDimensions"
    actions   = ["ec2:DescribeTags", "ec2:DescribeVolumes"]
    resources = ["*"]
  }

  statement {
    sid = "ShipLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = concat(local.log_group_arns, [for a in local.log_group_arns : "${a}:*"])
  }
}

resource "aws_iam_policy" "cloudwatch_agent" {
  name        = "${var.iam_name}-cloudwatch-agent"
  description = "CloudWatch Agent metrics and logs for ${var.name} only"
  policy      = data.aws_iam_policy_document.cloudwatch_agent.json
}

# --- Web tier ----------------------------------------------------------------

resource "aws_iam_role" "web" {
  name               = "${var.iam_name}-web"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "web_cloudwatch" {
  role       = aws_iam_role.web.name
  policy_arn = aws_iam_policy.cloudwatch_agent.arn
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.iam_name}-web"
  role = aws_iam_role.web.name
}

# --- App tier ----------------------------------------------------------------

resource "aws_iam_role" "app" {
  name               = "${var.iam_name}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "db_secret" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid       = "DecryptDatabaseSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "app_db_secret" {
  name   = "read-db-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.db_secret.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.cloudwatch_agent.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.iam_name}-app"
  role = aws_iam_role.app.name
}
