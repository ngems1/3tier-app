# Project 2 (ECS on Fargate), development environment. Own VPC, ALB and RDS,
# independent from the EC2 project; smaller and cheaper than prod.

module "stack" {
  source = "../../modules/ecs-stack"

  environment   = "dev"
  app_version   = var.app_version
  alarm_emails  = var.alarm_emails
  allow_destroy = var.allow_destroy

  vpc_cidr              = "10.76.0.0/16"
  public_subnet_cidrs   = ["10.76.1.0/24", "10.76.2.0/24", "10.76.3.0/24"]
  frontend_subnet_cidrs = ["10.76.4.0/24", "10.76.5.0/24", "10.76.6.0/24"]
  backend_subnet_cidrs  = ["10.76.7.0/24", "10.76.8.0/24", "10.76.9.0/24"]
  db_subnet_cidrs       = ["10.76.10.0/24", "10.76.11.0/24", "10.76.12.0/24"]
  excluded_zone_ids     = ["use1-az3"]
  single_nat_gateway    = true

  # No domain yet: served over HTTP at the load balancer's address (app_url
  # output). With a Route 53 hosted zone, set these two lines to get HTTPS
  # and ecs-dev.<domain> automatically:
  #   hosted_zone_name = "example.com"
  #   record_name      = "ecs-dev"

  frontend_min_count = 1
  frontend_max_count = 3
  backend_min_count  = 2
  backend_max_count  = 4

  db_instance_class               = "db.t3.small"
  db_allocated_storage            = 20
  db_max_allocated_storage        = 50
  db_multi_az                     = true
  db_backup_retention_days        = 7
  db_performance_insights_enabled = false

  deletion_protection = false
  log_retention_days  = 30
}
