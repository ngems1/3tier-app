# Production environment: NAT gateway per AZ, larger instances, deletion
# protection, final DB snapshot, longer backup and log retention.

module "stack" {
  source = "../../modules/app-stack"

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
  existing_vpc_id     = "vpc-0e13ae6de03f62cd5"
  vpc_cidr            = "172.31.0.0/16"
  public_subnet_cidrs = ["172.31.144.0/24", "172.31.145.0/24", "172.31.146.0/24"]
  web_subnet_cidrs    = ["172.31.147.0/24", "172.31.148.0/24", "172.31.149.0/24"]
  app_subnet_cidrs    = ["172.31.150.0/24", "172.31.151.0/24", "172.31.152.0/24"]
  db_subnet_cidrs     = ["172.31.153.0/24", "172.31.154.0/24", "172.31.155.0/24"]
  # use1-az3 does not offer many current instance types (including some t3
  # sizes), so the stack uses three of the other us-east-1 AZs.
  excluded_zone_ids = ["use1-az3"]

  single_nat_gateway = false

  # No domain yet: the app is served over HTTP at the load balancer's address
  # (see the app_url output). When you have a Route 53 hosted zone, set these
  # two lines and HTTPS, the certificate and prod.<domain> are created
  # automatically:
  #   hosted_zone_name = "example.com"
  #   record_name      = "prod"

  web_instance_type    = "t3.medium"
  app_instance_type    = "t3.medium"
  web_min_size         = 2
  web_max_size         = 6
  web_desired_capacity = 2
  app_min_size         = 2
  app_max_size         = 6
  app_desired_capacity = 2

  db_instance_class               = "db.t3.medium"
  db_allocated_storage            = 50
  db_max_allocated_storage        = 200
  db_multi_az                     = true
  db_backup_retention_days        = 30
  db_performance_insights_enabled = true

  deletion_protection = true
  log_retention_days  = 365
}
