# ACM certificate (DNS-validated in Route 53) for the public HTTPS listener,
# and the alias record that points the app's hostname at the web ALB.

data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

locals {
  fqdn = "${var.record_name}.${var.hosted_zone_name}"
}

resource "aws_acm_certificate" "this" {
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# The certificate covers exactly one name, so ACM asks for exactly one DNS
# validation record. Using a single resource (rather than for_each over
# domain_validation_options) keeps the plan valid before the certificate
# exists: Terraform can't plan a for_each whose keys are only known after apply.
locals {
  validation = one(aws_acm_certificate.this.domain_validation_options)
}

resource "aws_route53_record" "validation" {
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = local.validation.resource_record_name
  type            = local.validation.resource_record_type
  records         = [local.validation.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [aws_route53_record.validation.fqdn]
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
