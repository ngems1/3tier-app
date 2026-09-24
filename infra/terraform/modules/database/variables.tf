variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "subnet_ids" {
  description = "Isolated database subnets"
  type        = list(string)
}

variable "db_sg_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "engine_version" {
  description = "MySQL major/minor version, e.g. 8.4"
  type        = string
}

variable "parameter_group_family" {
  description = "Parameter group family matching engine_version, e.g. mysql8.4"
  type        = string
}

variable "instance_class" {
  type = string
}

variable "db_name" {
  type = string
}

variable "master_username" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  description = "Upper limit for storage autoscaling"
  type        = number
}

variable "multi_az" {
  type = bool
}

variable "backup_retention_period" {
  type = number
}

variable "deletion_protection" {
  type = bool
}

variable "skip_final_snapshot" {
  type = bool
}

variable "apply_immediately" {
  type = bool
}

variable "performance_insights_enabled" {
  type = bool
}

variable "iam_name" {
  description = "Name prefix for IAM roles, policies and instance profiles, e.g. cloudbatch818-three-tier-dev"
  type        = string
}
