# The complete 3-tier stack for one environment. Each environment under
# infra/terraform/environments/ calls this module with its own settings.

locals {
  name              = "${var.project}-${var.environment}"
  short_name        = "${var.short_project}-${var.environment}" # load balancer names: 32 characters max
  metrics_namespace = "${var.project}/${var.environment}"

  # Route 53 + ACM + HTTPS only when a domain is configured.
  use_domain = var.hosted_zone_name != ""

  # Deletion protection, unless the Destroy workflow is removing the stack.
  protect = var.deletion_protection && !var.allow_destroy
}

# ---------------------------------------------------------------------------
# Release AMIs: baked by Packer in CI and tagged with the git commit SHA.
# Deploying a version = pointing the launch templates at that version's AMIs.
# ---------------------------------------------------------------------------

data "aws_ami" "release" {
  for_each    = toset(["web", "app"])
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "tag:Project"
    values = [var.project]
  }

  filter {
    name   = "tag:Component"
    values = [each.key]
  }

  filter {
    name   = "tag:Version"
    values = [var.app_version]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Last release that passed its deployment checks. Terraform creates it; the
# pipeline (and deploy scripts) update it only after the rollout and smoke
# tests succeed, so a failed or rolled-back release is never recorded here.
# CI reads it for PR plans, and its history doubles as a deployment log.
resource "aws_ssm_parameter" "deployed_version" {
  #checkov:skip=CKV2_AWS_34:The value is a public git commit SHA, not a secret.
  name        = "/${var.project}/${var.environment}/deployed-version"
  description = "Git commit SHA of the last successful deployment to ${var.environment}"
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
  existing_vpc_id         = var.existing_vpc_id
  public_subnet_cidrs     = var.public_subnet_cidrs
  web_subnet_cidrs        = var.web_subnet_cidrs
  app_subnet_cidrs        = var.app_subnet_cidrs
  db_subnet_cidrs         = var.db_subnet_cidrs
  single_nat_gateway      = var.single_nat_gateway
  excluded_zone_ids       = var.excluded_zone_ids
  flow_log_retention_days = var.log_retention_days
  kms_key_arn             = module.kms.key_arn
}

module "security" {
  source   = "../security"
  name     = local.name
  vpc_id   = module.network.vpc_id
  app_port = var.app_port
}

module "dns" {
  count            = local.use_domain ? 1 : 0
  source           = "../dns"
  hosted_zone_name = var.hosted_zone_name
  record_name      = var.record_name
  alb_dns_name     = module.alb.web_alb_dns_name
  alb_zone_id      = module.alb.web_alb_zone_id
}

module "alb" {
  source              = "../alb"
  name                = local.name
  short_name          = local.short_name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  app_subnet_ids      = module.network.app_subnet_ids
  alb_public_sg_id    = module.security.alb_public_sg_id
  app_alb_sg_id       = module.security.app_alb_sg_id
  app_port            = var.app_port
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

module "compute" {
  source      = "../compute"
  name        = local.name
  iam_name    = local.name
  environment = var.environment
  app_version = var.app_version

  web_ami_id        = data.aws_ami.release["web"].id
  app_ami_id        = data.aws_ami.release["app"].id
  web_instance_type = var.web_instance_type
  app_instance_type = var.app_instance_type

  web_subnet_ids       = module.network.web_subnet_ids
  app_subnet_ids       = module.network.app_subnet_ids
  web_sg_id            = module.security.web_sg_id
  app_sg_id            = module.security.app_sg_id
  web_target_group_arn = module.alb.web_target_group_arn
  app_target_group_arn = module.alb.app_target_group_arn
  app_alb_dns_name     = module.alb.app_alb_dns_name

  web_min_size         = var.web_min_size
  web_max_size         = var.web_max_size
  web_desired_capacity = var.web_desired_capacity
  app_min_size         = var.app_min_size
  app_max_size         = var.app_max_size
  app_desired_capacity = var.app_desired_capacity

  db_host       = module.database.address
  db_port       = module.database.port
  db_name       = module.database.db_name
  db_secret_arn = module.database.master_user_secret_arn
  kms_key_arn   = module.kms.key_arn

  # Taken from the observability outputs so the log groups exist before
  # instances boot and start shipping logs.
  metrics_namespace  = local.metrics_namespace
  web_log_group_name = module.observability.log_group_names["web"]
  app_log_group_name = module.observability.log_group_names["app"]
  log_group_names    = values(module.observability.log_group_names)
}

module "observability" {
  source             = "../observability"
  name               = local.name
  environment        = var.environment
  kms_key_arn        = module.kms.key_arn
  log_retention_days = var.log_retention_days
  alarm_emails       = var.alarm_emails
  metrics_namespace  = local.metrics_namespace

  web_alb_arn_suffix          = module.alb.web_alb_arn_suffix
  web_target_group_arn_suffix = module.alb.web_target_group_arn_suffix
  app_alb_arn_suffix          = module.alb.app_alb_arn_suffix
  app_target_group_arn_suffix = module.alb.app_target_group_arn_suffix
  web_asg_name                = "${local.name}-web"
  app_asg_name                = "${local.name}-app"
  web_min_size                = var.web_min_size
  app_min_size                = var.app_min_size
  db_instance_id              = module.database.instance_id
}
