# Public ALB for the ECS services: HTTPS (when a domain is configured) with
# WAF, path-based routing (/api/* -> backend, everything else -> frontend) and
# access logs in S3. Targets are Fargate task IPs.

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

# ---------------------------------------------------------------------------
# Access log bucket (ALB log delivery only supports SSE-S3)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_145:ALB access log delivery only supports SSE-S3 (AES256), not SSE-KMS.
  #checkov:skip=CKV_AWS_18:This bucket is itself the log destination; logging it to another bucket adds no value here.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for access logs in this project.
  #checkov:skip=CKV2_AWS_62:No consumers need S3 event notifications for access logs.
  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy_logs
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "AlbLogDeliveryLegacyRegions"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  statement {
    sid       = "AlbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# ---------------------------------------------------------------------------
# Load balancer and target groups
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:HTTP redirects to HTTPS whenever a domain is configured (enable_https); without one, HTTP-only is a temporary mode.
  name                       = var.short_name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "service" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; traffic to tasks stays inside the VPC on private subnets.
  for_each = var.services

  name                 = "${var.short_name}-${each.key}"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.name}-${each.key}" }
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------

# With a domain: port 80 redirects to HTTPS, and HTTPS serves the app.
resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[var.default_service].arn
  }
}

# Without a domain yet: plain HTTP (temporary).
resource "aws_lb_listener" "http_only" {
  #checkov:skip=CKV_AWS_2:Temporary HTTP-only mode until a domain exists; HTTPS is enabled automatically when hosted_zone_name is set.
  #checkov:skip=CKV_AWS_103:See CKV_AWS_2.
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[var.default_service].arn
  }
}

locals {
  serving_listener_arn = var.enable_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http_only[0].arn
}

# Path-based routing, e.g. /api/* -> backend.
resource "aws_lb_listener_rule" "path" {
  for_each     = { for k, v in var.services : k => v if length(v.path_patterns) > 0 }
  listener_arn = local.serving_listener_arn
  priority     = each.value.priority

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }
}

# ---------------------------------------------------------------------------
# WAF on the ALB, with logging
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "web" {
  name  = "${var.name}-web"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      AWSManagedRulesCommonRuleSet          = 1
      AWSManagedRulesKnownBadInputsRuleSet  = 2
      AWSManagedRulesAmazonIpReputationList = 3
    }
    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "web" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.web.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment decision set through log_retention_days (365 days in prod).
  # WAF requires the log group name to start with "aws-waf-logs-".
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_wafv2_web_acl_logging_configuration" "web" {
  resource_arn            = aws_wafv2_web_acl.web.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}

