variable "project" {
  description = "Prefix for every resource name"
  type        = string
  default     = "cloudbatch818-three-tier-ecs"
}

variable "short_project" {
  description = "Shorter prefix for names limited to 32 characters (target groups)"
  type        = string
  default     = "cloudbatch818-ecs"
}

variable "ecr_repository_prefix" {
  description = "ECR repositories are <prefix>-frontend and <prefix>-backend (created by the bootstrap)"
  type        = string
  default     = "cloudbatch818-three-tier"
}

variable "environment" {
  type = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters, digits or dashes."
  }
}

variable "app_version" {
  description = "Release to deploy: the git commit SHA whose images were pushed to ECR"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.app_version))
    error_message = "app_version must be a git commit SHA."
  }
}

# --- Network -----------------------------------------------------------------

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "frontend_subnet_cidrs" {
  type = list(string)
}

variable "backend_subnet_cidrs" {
  type = list(string)
}

variable "db_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type = bool
}

variable "excluded_zone_ids" {
  type    = list(string)
  default = []
}

# --- DNS / TLS (optional until a domain exists) ------------------------------

variable "hosted_zone_name" {
  type    = string
  default = ""
}

variable "record_name" {
  type    = string
  default = ""
}

# --- Services ----------------------------------------------------------------

variable "frontend_cpu" {
  type    = number
  default = 256
}

variable "frontend_memory" {
  type    = number
  default = 512
}

variable "frontend_min_count" {
  type = number
}

variable "frontend_max_count" {
  type = number
}

variable "backend_cpu" {
  type    = number
  default = 512
}

variable "backend_memory" {
  type    = number
  default = 1024
}

variable "backend_min_count" {
  type = number
}

variable "backend_max_count" {
  type = number
}

# --- Database ----------------------------------------------------------------

variable "db_engine_version" {
  type    = string
  default = "8.4"
}

variable "db_parameter_group_family" {
  type    = string
  default = "mysql8.4"
}

variable "db_instance_class" {
  type = string
}

variable "db_name" {
  type    = string
  default = "webappdb"
}

variable "db_master_username" {
  type    = string
  default = "appadmin"
}

variable "db_allocated_storage" {
  type = number
}

variable "db_max_allocated_storage" {
  type = number
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_performance_insights_enabled" {
  type = bool
}

# --- Protection and observability ---------------------------------------------

variable "deletion_protection" {
  type = bool
}

variable "allow_destroy" {
  description = "Set only by the Destroy workflow: turns off deletion protection on the load balancers and database (prod still keeps a final DB snapshot) so the stack can be removed"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type = number
}

variable "alarm_emails" {
  type    = list(string)
  default = []
}
