# Project 2 (ECS on Fargate), production environment: NAT gateway per AZ,
# at least two tasks per service, deletion protection, longer retention.

module "stack" {
  source = "../../modules/ecs-stack"

  environment   = "prod"
  app_version   = var.app_version
  alarm_emails  = var.alarm_emails
  allow_destroy = var.allow_destroy

  vpc_cidr              = "10.81.0.0/16"
  public_subnet_cidrs   = ["10.81.1.0/24", "10.81.2.0/24", "10.81.3.0/24"]
  frontend_subnet_cidrs = ["10.81.4.0/24", "10.81.5.0/24", "10.81.6.0/24"]
  backend_subnet_cidrs  = ["10.81.7.0/24", "10.81.8.0/24", "10.81.9.0/24"]
  db_subnet_cidrs       = ["10.81.10.0/24", "10.81.11.0/24", "10.81.12.0/24"]
  excluded_zone_ids     = ["use1-az3"]
  single_nat_gateway    = false

  # No domain yet: served over HTTP at the load balancer's address (app_url
  # output). With a Route 53 hosted zone, set these two lines to get HTTPS
  # and ecs.<domain> automatically:
  #   hosted_zone_name = "example.com"
  #   record_name      = "ecs"

  frontend_min_count = 2
  frontend_max_count = 6
  backend_min_count  = 2
  backend_max_count  = 6

  db_instance_class               = "db.t3.medium"
  db_allocated_storage            = 50
  db_max_allocated_storage        = 200
  db_multi_az                     = true
  db_backup_retention_days        = 30
  db_performance_insights_enabled = true

  deletion_protection = true
  log_retention_days  = 365
}
