# Development environment: same architecture as prod, smaller and cheaper
# (single NAT gateway, smaller instances, no deletion protection).

module "stack" {
  source = "../../modules/app-stack"

  environment   = "dev"
  app_version   = var.app_version
  alarm_emails  = var.alarm_emails
  allow_destroy = var.allow_destroy

  # The account has reached its VPC quota in us-east-1, so this stack is built
  # inside the existing default VPC (172.31.0.0/16) on its own free /24 ranges.
  # Each environment uses a separate block: dev 172.31.128-139, prod
  # 172.31.144-155, ecs-dev 172.31.160-171, ecs-prod 172.31.176-187. To give
  # the stack its own VPC again, delete existing_vpc_id and set a new
  # vpc_cidr and subnet ranges (e.g. 10.x.0.0/16).
  existing_vpc_id     = "vpc-0e13ae6de03f62cd5"
  vpc_cidr            = "172.31.0.0/16"
  public_subnet_cidrs = ["172.31.128.0/24", "172.31.129.0/24", "172.31.130.0/24"]
  web_subnet_cidrs    = ["172.31.131.0/24", "172.31.132.0/24", "172.31.133.0/24"]
  app_subnet_cidrs    = ["172.31.134.0/24", "172.31.135.0/24", "172.31.136.0/24"]
  db_subnet_cidrs     = ["172.31.137.0/24", "172.31.138.0/24", "172.31.139.0/24"]
  # use1-az3 does not offer many current instance types (including some t3
  # sizes), so the stack uses three of the other us-east-1 AZs.
  excluded_zone_ids = ["use1-az3"]

  single_nat_gateway = true

  # No domain yet: the app is served over HTTP at the load balancer's address
  # (see the app_url output). When you have a Route 53 hosted zone, set these
  # two lines and HTTPS, the certificate and dev.<domain> are created
  # automatically:
  #   hosted_zone_name = "example.com"
  #   record_name      = "dev"

  web_instance_type    = "t3.small"
  app_instance_type    = "t3.small"
  web_min_size         = 1
  web_max_size         = 3
  web_desired_capacity = 1
  app_min_size         = 2
  app_max_size         = 4
  app_desired_capacity = 2

  db_instance_class               = "db.t3.small"
  db_allocated_storage            = 20
  db_max_allocated_storage        = 50
  db_multi_az                     = true
  db_backup_retention_days        = 7
  db_performance_insights_enabled = false

  deletion_protection = false
  log_retention_days  = 30
}
