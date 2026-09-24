variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "environment" {
  type = string
}

variable "app_version" {
  description = "Release version (git commit SHA) being deployed"
  type        = string
}

variable "web_ami_id" {
  type = string
}

variable "app_ami_id" {
  type = string
}

variable "web_instance_type" {
  type = string
}

variable "app_instance_type" {
  type = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 20
}

variable "web_subnet_ids" {
  type = list(string)
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "web_sg_id" {
  type = string
}

variable "app_sg_id" {
  type = string
}

variable "web_target_group_arn" {
  type = string
}

variable "app_target_group_arn" {
  type = string
}

variable "app_alb_dns_name" {
  type = string
}

variable "web_min_size" {
  type = number
}

variable "web_max_size" {
  type = number
}

variable "web_desired_capacity" {
  type = number
}

variable "app_min_size" {
  type = number
}

variable "app_max_size" {
  type = number
}

variable "app_desired_capacity" {
  type = number
}

variable "cpu_target_percent" {
  description = "Average CPU the target-tracking policy aims for"
  type        = number
  default     = 50
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "metrics_namespace" {
  description = "CloudWatch namespace for CloudWatch Agent metrics (memory, disk)"
  type        = string
}

variable "web_log_group_name" {
  type = string
}

variable "app_log_group_name" {
  type = string
}

variable "log_group_names" {
  description = "Log groups the instances may write to"
  type        = list(string)
}

variable "iam_name" {
  description = "Name prefix for IAM roles, policies and instance profiles, e.g. cloudbatch818-three-tier-dev"
  type        = string
}
