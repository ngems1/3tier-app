# Offline tests for the ECS stack (`terraform test` in modules/ecs-stack).
# The AWS provider is mocked, so these run in CI without credentials and check
# the wiring and the controls Project 2 relies on.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address = "cloudbatch818-three-tier-test.abc.us-east-1.rds.amazonaws.com"
      port    = 3306
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-1234"
        kms_key_id    = "key"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  # Resources whose ARNs are validated by other resources that reference them.
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/0123456789abcdef"
      arn_suffix = "app/mock/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/0123456789abcdef"
      arn_suffix = "targetgroup/mock/0123456789abcdef"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/mock/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock"
      domain_validation_options = [{
        domain_name           = "ecs-test.example.com"
        resource_record_name  = "_0123456789abcdef.ecs-test.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_fedcba9876543210.acm-validations.aws."
      }]
    }
  }


  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }

  # ECS-specific mocks
  mock_data "aws_ecr_repository" {
    defaults = {
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/cloudbatch818-three-tier-app"
    }
  }

  mock_data "aws_ecr_image" {
    defaults = {
      image_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:cluster/mock"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/mock:1"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock/0123456789abcdef/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener_rule" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/mock/0123456789abcdef/0123456789abcdef/0123456789abcdef"
    }
  }
}

variables {
  environment           = "test"
  app_version           = "0123456789abcdef0123456789abcdef01234567"
  vpc_cidr              = "10.91.0.0/16"
  public_subnet_cidrs   = ["10.91.1.0/24", "10.91.2.0/24", "10.91.3.0/24"]
  frontend_subnet_cidrs = ["10.91.4.0/24", "10.91.5.0/24", "10.91.6.0/24"]
  backend_subnet_cidrs  = ["10.91.7.0/24", "10.91.8.0/24", "10.91.9.0/24"]
  db_subnet_cidrs       = ["10.91.10.0/24", "10.91.11.0/24", "10.91.12.0/24"]
  single_nat_gateway    = false
  hosted_zone_name      = "example.com"
  record_name           = "ecs-test"

  frontend_min_count = 2
  frontend_max_count = 4
  backend_min_count  = 2
  backend_max_count  = 6

  db_instance_class               = "db.t3.medium"
  db_allocated_storage            = 20
  db_max_allocated_storage        = 50
  db_multi_az                     = true
  db_backup_retention_days        = 7
  db_performance_insights_enabled = true
  deletion_protection             = true
  log_retention_days              = 365
}

run "enterprise_controls" {
  command = apply

  # Tasks run exactly the image that CI built and scanned.
  assert {
    condition     = alltrue([for img in values(output.images) : can(regex("@sha256:[0-9a-f]{64}$", img))])
    error_message = "Task images must be pinned by digest"
  }

  # Safe rolling deployments with automatic rollback.
  assert {
    condition     = alltrue([for c in values(module.ecs.controls) : c.circuit_breaker_rollback && c.min_healthy_percent == 100])
    error_message = "Services must keep full capacity during deploys and roll back failed deployments"
  }

  # Tasks live in private subnets only.
  assert {
    condition     = alltrue([for c in values(module.ecs.controls) : c.public_ip == false])
    error_message = "Tasks must not get public IP addresses"
  }

  assert {
    condition     = alltrue([for c in values(module.ecs.controls) : c.container_insights == "enabled"])
    error_message = "Container Insights must be enabled"
  }

  # Database credentials come from Secrets Manager at runtime, never from the task definition.
  assert {
    condition     = local.services.backend.environment.DB_SECRET_ARN == module.database.master_user_secret_arn && !contains(keys(local.services.backend.environment), "DB_PASSWORD")
    error_message = "The backend must read its database credentials from Secrets Manager"
  }

  assert {
    condition     = local.services.backend.read_db_secret && !local.services.frontend.read_db_secret
    error_message = "Only the backend task role may read the database secret"
  }

  assert {
    condition     = local.services.backend.readonly_root
    error_message = "The backend container must run with a read-only root filesystem"
  }

  # Environment-specific names, within AWS's limits, all with the required prefix.
  assert {
    condition     = module.ecs.cluster_name == "cloudbatch818-three-tier-ecs-test" && module.database.instance_id == "cloudbatch818-three-tier-ecs-test"
    error_message = "Names must include the environment"
  }

  assert {
    condition     = length("${local.short_name}-frontend") <= 32
    error_message = "Load balancer and target group names must fit in 32 characters"
  }

  assert {
    condition     = alltrue([for n in module.ecs.iam_names : startswith(n, "cloudbatch818-three-tier-ecs-test-")])
    error_message = "IAM names must start with the project prefix"
  }

  # High availability: one NAT gateway per AZ when single_nat_gateway = false.
  assert {
    condition     = module.network.nat_gateway_count == 3
    error_message = "Expected one NAT gateway per AZ"
  }

  # Release tracking
  assert {
    condition     = aws_ssm_parameter.deployed_version.name == "/cloudbatch818-three-tier-ecs/test/deployed-version" && aws_ssm_parameter.deployed_version.value == var.app_version
    error_message = "Deployed version parameter must record the release SHA"
  }

  assert {
    condition     = output.app_url == "https://ecs-test.example.com"
    error_message = "Unexpected application URL"
  }
}

run "rejects_non_sha_versions" {
  command = plan

  variables {
    app_version = "latest"
  }

  expect_failures = [var.app_version]
}

run "works_without_a_domain" {
  command = apply

  variables {
    hosted_zone_name = ""
    record_name      = ""
  }

  assert {
    condition     = startswith(output.app_url, "http://")
    error_message = "Without a domain the app must be served over HTTP on the load balancer address"
  }
}

run "deletion_protection_until_destroy" {
  command = plan

  assert {
    condition     = local.protect
    error_message = "With deletion_protection = true, the load balancers and database must be protected"
  }
}

run "destroy_workflow_unlocks_protection" {
  command = plan

  variables {
    allow_destroy = true
  }

  assert {
    condition     = !local.protect
    error_message = "allow_destroy must turn deletion protection off so the Destroy workflow can remove the stack"
  }
}
