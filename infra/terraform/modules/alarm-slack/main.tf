# Posts CloudWatch alarms to Slack: a small Lambda function subscribed to the
# environment's alarm topic. The webhook URL is read at run time from an
# encrypted SSM parameter that the deploy pipeline writes from the
# SLACK_WEBHOOK_URL GitHub secret, so it never appears in Terraform code,
# plans or state. Without that parameter the function does nothing.
#
# lambda.zip is built reproducibly by build.py from lambda/alarm_to_slack.py
# and committed (CI checks it is up to date).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  function_name = "${var.name}-alarm-to-slack"
  arn_prefix    = "arn:${data.aws_partition.current.partition}"
  region        = data.aws_region.current.region
  account_id    = data.aws_caller_identity.current.account_id
  parameter_arn = "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter${var.webhook_parameter_name}"
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment decision set through log_retention_days (365 days in prod).
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.iam_name}-alarm-to-slack"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_111:kms:Decrypt is limited by the kms:ViaService condition to SSM in this region (the parameter uses the AWS-managed aws/ssm key, whose ARN is only known once it exists).
  #checkov:skip=CKV_AWS_356:See CKV_AWS_111.
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "ReadWebhookParameter"
    actions   = ["ssm:GetParameter"]
    resources = [local.parameter_arn]
  }

  statement {
    sid       = "DecryptWebhookParameter"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "alarm-to-slack"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_116:Invoked asynchronously by SNS, which retries failed deliveries; a failed post is also logged. A dead-letter queue would only hold alarm copies.
  #checkov:skip=CKV_AWS_117:The function only calls SSM and Slack over HTTPS and touches no VPC resource; putting it in the VPC would only add a NAT dependency.
  #checkov:skip=CKV_AWS_173:Its environment variables hold no secrets (a parameter name and a label); the webhook stays in the encrypted SSM parameter.
  #checkov:skip=CKV_AWS_272:Code signing adds a signing profile for a single small function whose zip is built reproducibly and checked in CI.
  #checkov:skip=CKV_AWS_115:Alarm traffic is tiny; reserving concurrency would take capacity from the account's shared pool for no benefit.
  #checkov:skip=CKV_AWS_50:X-Ray tracing isn't useful for a single outbound HTTPS call; errors are in the function's log group.
  function_name    = local.function_name
  description      = "Posts ${var.stack_label} CloudWatch alarms to Slack"
  role             = aws_iam_role.this.arn
  runtime          = "python3.12"
  handler          = "alarm_to_slack.handler"
  filename         = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      WEBHOOK_PARAMETER = var.webhook_parameter_name
      STACK_LABEL       = var.stack_label
    }
  }

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowAlarmTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.sns]
}
