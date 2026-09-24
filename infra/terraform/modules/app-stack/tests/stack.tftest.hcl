# Offline tests for the whole stack (`terraform test` in modules/app-stack).
# The AWS provider is mocked, so these run in CI without credentials and check
# the wiring and the enterprise controls the project plan requires.

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
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

variables {
  environment          = "test"
  app_version          = "0123456789abcdef0123456789abcdef01234567"
  vpc_cidr             = "10.90.0.0/16"
  public_subnet_cidrs  = ["10.90.1.0/24", "10.90.2.0/24", "10.90.3.0/24"]
  web_subnet_cidrs     = ["10.90.4.0/24", "10.90.5.0/24", "10.90.6.0/24"]
  app_subnet_cidrs     = ["10.90.7.0/24", "10.90.8.0/24", "10.90.9.0/24"]
  db_subnet_cidrs      = ["10.90.10.0/24", "10.90.11.0/24", "10.90.12.0/24"]
  single_nat_gateway   = false
  hosted_zone_name     = "example.com"
  record_name          = "test"
  web_instance_type    = "t3.small"
  app_instance_type    = "t3.small"
  web_min_size         = 2
  web_max_size         = 4
  web_desired_capacity = 2
  app_min_size         = 2
  app_max_size         = 4
  app_desired_capacity = 2

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

  # Names are unique per environment, so dev and prod can share an account/region.
  assert {
    condition     = module.compute.web_asg_name == "cloudbatch818-three-tier-test-web" && module.compute.app_asg_name == "cloudbatch818-three-tier-test-app"
    error_message = "ASG names must include the environment"
  }

  # Encryption at rest
  assert {
    condition     = module.database.instance_id == "cloudbatch818-three-tier-test"
    error_message = "RDS identifier must include the environment"
  }

  assert {
    condition     = alltrue([for lt in module.compute.launch_templates : lt.encrypted_root && lt.imdsv2])
    error_message = "Launch templates must use encrypted EBS and require IMDSv2"
  }

  # High availability: one NAT gateway per AZ when single_nat_gateway = false
  assert {
    condition     = module.network.nat_gateway_count == 3
    error_message = "Expected one NAT gateway per AZ"
  }

  # Every IAM name starts with the required prefix
  assert {
    condition     = alltrue([for n in module.compute.iam_names : startswith(n, "cloudbatch818-three-tier-test-")])
    error_message = "IAM names must start with cloudbatch818"
  }

  # Release tracking
  assert {
    condition     = aws_ssm_parameter.deployed_version.value == var.app_version
    error_message = "Deployed version parameter must record the release SHA"
  }

  assert {
    condition     = output.app_url == "https://test.example.com"
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
