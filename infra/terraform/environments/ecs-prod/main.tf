# Project 2 (ECS on Fargate), production environment: NAT gateway per AZ,
# at least two tasks per service, deletion protection, longer retention.

module "stack" {
  source = "../../modules/ecs-stack"

  environment   = "prod"
  app_version   = var.app_version
  alarm_emails  = var.alarm_emails
  allow_destroy = var.allow_destroy

  # The account has reached its VPC quota in us-east-1, so this stack is built
  # inside the existing default VPC (172.31.0.0/16) on its own free /24 ranges.
  # Each environment uses a separate block: dev 172.31.128-139, prod
  # 172.31.144-155, ecs-dev 172.31.160-171, ecs-prod 172.31.176-187. To give
  # the stack its own VPC again, delete existing_vpc_id and set a new
  # vpc_cidr and subnet ranges (e.g. 10.x.0.0/16).
  existing_vpc_id       = "vpc-0e13ae6de03f62cd5"
  vpc_cidr              = "172.31.0.0/16"
  public_subnet_cidrs   = ["172.31.176.0/24", "172.31.177.0/24", "172.31.178.0/24"]
  frontend_subnet_cidrs = ["172.31.179.0/24", "172.31.180.0/24", "172.31.181.0/24"]
  backend_subnet_cidrs  = ["172.31.182.0/24", "172.31.183.0/24", "172.31.184.0/24"]
  db_subnet_cidrs       = ["172.31.185.0/24", "172.31.186.0/24", "172.31.187.0/24"]
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
