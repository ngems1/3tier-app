# Production environment: NAT gateway per AZ, larger instances, deletion
# protection, final DB snapshot, longer backup and log retention.

module "stack" {
  source = "../../modules/app-stack"

  environment   = "prod"
  app_version   = var.app_version
  alarm_emails  = var.alarm_emails
  allow_destroy = var.allow_destroy

  vpc_cidr            = "10.80.0.0/16"
  public_subnet_cidrs = ["10.80.1.0/24", "10.80.2.0/24", "10.80.3.0/24"]
  web_subnet_cidrs    = ["10.80.4.0/24", "10.80.5.0/24", "10.80.6.0/24"]
  app_subnet_cidrs    = ["10.80.7.0/24", "10.80.8.0/24", "10.80.9.0/24"]
  db_subnet_cidrs     = ["10.80.10.0/24", "10.80.11.0/24", "10.80.12.0/24"]
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
