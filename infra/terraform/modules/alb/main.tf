# Public web ALB (HTTPS + WAF) in front of the web tier, and an internal ALB
# in front of the app tier. Both write access logs to an S3 bucket.

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
# Public web ALB
# ---------------------------------------------------------------------------

resource "aws_lb" "web" {
  #checkov:skip=CKV_AWS_150:Deletion protection is set per environment: on in prod (deletion_protection = true), off in dev so the Destroy workflow can remove it.
  #checkov:skip=CKV2_AWS_20:HTTP redirects to HTTPS whenever a domain is configured (enable_https); without one, HTTP-only is a temporary mode.
  name                       = "${var.short_name}-web"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_public_sg_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "web"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "web" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the public ALB; traffic to the web instances stays inside the VPC on private subnets.
  name                 = "${var.short_name}-web"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# With a domain (enable_https = true): port 80 redirects to HTTPS on 443.
resource "aws_lb_listener" "web_http" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.web.arn
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

resource "aws_lb_listener" "web_https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Without a domain yet (enable_https = false): serve plain HTTP on port 80.
# Temporary: setting hosted_zone_name in the environment switches to HTTPS.
resource "aws_lb_listener" "web_http_only" {
  #checkov:skip=CKV_AWS_2:Temporary HTTP-only mode until a domain exists; HTTPS is enabled automatically when hosted_zone_name is set.
  #checkov:skip=CKV_AWS_103:See CKV_AWS_2.
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------------------------
# WAF on the public ALB, with logging
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
  resource_arn = aws_lb.web.arn
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

# ---------------------------------------------------------------------------
# Internal app ALB (web tier -> app tier)
# ---------------------------------------------------------------------------

resource "aws_lb" "app" {
  #checkov:skip=CKV_AWS_150:Deletion protection is set per environment: on in prod (deletion_protection = true), off in dev so the Destroy workflow can remove it.
  #checkov:skip=CKV2_AWS_20:Internal-only ALB reached from the web tier inside the VPC; TLS terminates at the public edge.
  #checkov:skip=CKV2_AWS_28:Internal-only ALB, not reachable from the internet; WAF protects the public entry point.
  name                       = "${var.short_name}-app"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [var.app_alb_sg_id]
  subnets                    = var.app_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "app"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:Traffic stays inside the VPC between the internal ALB and private app instances.
  name                 = "${var.short_name}-app"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "app" {
  #checkov:skip=CKV_AWS_2:Internal-only listener; traffic never leaves the VPC and TLS terminates at the public ALB.
  #checkov:skip=CKV_AWS_103:Internal-only listener; see CKV_AWS_2.
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
