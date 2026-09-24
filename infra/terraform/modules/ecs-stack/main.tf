# Project 2: the same 3-tier application on Amazon ECS (Fargate).
#
#   Internet -> WAF -> ALB -> /api/*  -> backend service  (FastAPI, private subnets)
#                          -> other   -> frontend service (Nginx + React, private subnets)
#   backend -> RDS MySQL (isolated subnets, TLS, credentials from Secrets Manager)
#
# Reuses the network, kms, database and dns modules from Project 1, so both
# projects share the same baseline controls.

locals {
  name       = "${var.project}-${var.environment}"
  short_name = "${var.short_project}-${var.environment}"
  use_domain = var.hosted_zone_name != ""

  # Deletion protection, unless the Destroy workflow is removing the stack.
  protect = var.deletion_protection && !var.allow_destroy

  images = {
    frontend = "${data.aws_ecr_repository.app["frontend"].repository_url}@${data.aws_ecr_image.release["frontend"].image_digest}"
    backend  = "${data.aws_ecr_repository.app["backend"].repository_url}@${data.aws_ecr_image.release["backend"].image_digest}"
  }

  services = {
    frontend = {
      image          = local.images.frontend
      port           = 8080
      cpu            = var.frontend_cpu
      memory         = var.frontend_memory
      desired_count  = var.frontend_min_count
      min_count      = var.frontend_min_count
      max_count      = var.frontend_max_count
      health_command = "wget -qO- http://127.0.0.1:8080/healthz || exit 1"
      readonly_root  = false
      read_db_secret = false
      environment = {
        # The ALB sends /api/* straight to the backend service; this proxy
        # target is only used if a request reaches the frontend directly.
        BACKEND_URL  = "localhost:8000"
        DNS_RESOLVER = "169.254.169.253"
      }
    }
    backend = {
      image          = local.images.backend
      port           = 8000
      cpu            = var.backend_cpu
      memory         = var.backend_memory
      desired_count  = var.backend_min_count
      min_count      = var.backend_min_count
      max_count      = var.backend_max_count
      health_command = "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status == 200 else 1)\""
      readonly_root  = true
      read_db_secret = true
      environment = {
        APP_VERSION    = var.app_version
        AWS_REGION     = data.aws_region.current.region
        DB_HOST        = module.database.address
        DB_PORT        = tostring(module.database.port)
        DB_NAME        = module.database.db_name
        DB_SECRET_ARN  = module.database.master_user_secret_arn
        DB_SSL_CA      = "/etc/pki/rds/global-bundle.pem"
        DB_INIT_SCHEMA = "true"
      }
    }
  }
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Release images: must already be in ECR with the release's commit SHA tag
# (pushed and scanned by CI). The plan fails if they're missing. Tasks are
# pinned to the image digest.
# ---------------------------------------------------------------------------

data "aws_ecr_repository" "app" {
  for_each = toset(["frontend", "backend"])
  name     = "${var.ecr_repository_prefix}-${each.key}"
}

data "aws_ecr_image" "release" {
  for_each        = toset(["frontend", "backend"])
  repository_name = data.aws_ecr_repository.app[each.key].name
  image_tag       = var.app_version
}

# Last release that passed its deployment checks. Terraform creates it; the
# pipeline (and deploy scripts) update it only after the rollout and smoke
# tests succeed, so a failed or rolled-back release is never recorded here.
resource "aws_ssm_parameter" "deployed_version" {
  #checkov:skip=CKV2_AWS_34:The value is a public git commit SHA, not a secret.
  name        = "/${var.project}/${var.environment}/deployed-version"
  description = "Git commit SHA of the last successful deployment to ECS ${var.environment}"
  type        = "String"
  value       = var.app_version

  lifecycle {
    ignore_changes = [value]
  }
}

module "kms" {
  source = "../kms"
  name   = local.name
}

module "network" {
  source                  = "../network"
  name                    = local.name
  iam_name                = local.name
  environment             = var.environment
  cidr_block              = var.vpc_cidr
  public_subnet_cidrs     = var.public_subnet_cidrs
  web_subnet_cidrs        = var.frontend_subnet_cidrs
  app_subnet_cidrs        = var.backend_subnet_cidrs
  db_subnet_cidrs         = var.db_subnet_cidrs
  single_nat_gateway      = var.single_nat_gateway
  excluded_zone_ids       = var.excluded_zone_ids
  flow_log_retention_days = var.log_retention_days
  kms_key_arn             = module.kms.key_arn
}

module "security" {
  source        = "../ecs-security"
  name          = local.name
  vpc_id        = module.network.vpc_id
  frontend_port = 8080
  backend_port  = 8000
}

module "dns" {
  count            = local.use_domain ? 1 : 0
  source           = "../dns"
  hosted_zone_name = var.hosted_zone_name
  record_name      = var.record_name
  alb_dns_name     = module.alb.alb_dns_name
  alb_zone_id      = module.alb.alb_zone_id
}

module "alb" {
  source            = "../ecs-alb"
  name              = local.name
  short_name        = local.short_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  default_service   = "frontend"
  services = {
    frontend = { port = 8080, health_check_path = "/healthz", path_patterns = [], priority = 0 }
    backend  = { port = 8000, health_check_path = "/healthz", path_patterns = ["/api/*"], priority = 10 }
  }
  enable_https        = local.use_domain
  certificate_arn     = local.use_domain ? module.dns[0].certificate_arn : null
  deletion_protection = local.protect
  kms_key_arn         = module.kms.key_arn
  log_retention_days  = var.log_retention_days
  force_destroy_logs  = !local.protect
}

module "database" {
  source                       = "../database"
  name                         = local.name
  iam_name                     = local.name
  subnet_ids                   = module.network.db_subnet_ids
  db_sg_id                     = module.security.db_sg_id
  kms_key_arn                  = module.kms.key_arn
  engine_version               = var.db_engine_version
  parameter_group_family       = var.db_parameter_group_family
  instance_class               = var.db_instance_class
  db_name                      = var.db_name
  master_username              = var.db_master_username
  allocated_storage            = var.db_allocated_storage
  max_allocated_storage        = var.db_max_allocated_storage
  multi_az                     = var.db_multi_az
  backup_retention_period      = var.db_backup_retention_days
  deletion_protection          = local.protect
  skip_final_snapshot          = !var.deletion_protection
  apply_immediately            = !local.protect
  performance_insights_enabled = var.db_performance_insights_enabled
}

module "ecs" {
  source   = "../ecs"
  name     = local.name
  iam_name = local.name
  services = local.services

  subnet_ids = {
    frontend = module.network.web_subnet_ids
    backend  = module.network.app_subnet_ids
  }
  security_group_ids = {
    frontend = module.security.frontend_sg_id
    backend  = module.security.backend_sg_id
  }
  target_group_arns    = module.alb.target_group_arns
  routing_dependencies = module.alb.listener_rule_arns

  db_secret_arn      = module.database.master_user_secret_arn
  kms_key_arn        = module.kms.key_arn
  log_retention_days = var.log_retention_days
}

module "observability" {
  source         = "../ecs-observability"
  name           = local.name
  kms_key_arn    = module.kms.key_arn
  alarm_emails   = var.alarm_emails
  cluster_name   = module.ecs.cluster_name
  alb_arn_suffix = module.alb.alb_arn_suffix
  db_instance_id = module.database.instance_id
  services = {
    for k, s in local.services : k => {
      service_name = module.ecs.service_names[k]
      min_count    = s.min_count
      tg_suffix    = module.alb.target_group_arn_suffixes[k]
    }
  }
}
