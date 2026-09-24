variable "project" {
  description = "Prefix for every resource name and the AMI Project tag"
  type        = string
  default     = "cloudbatch818-three-tier"
}

variable "short_project" {
  description = "Shorter prefix for load balancer and target group names (AWS limits them to 32 characters)"
  type        = string
  default     = "cloudbatch818-3t"
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters, digits or dashes."
  }
}

variable "app_version" {
  description = "Release to deploy: the git commit SHA whose AMIs were baked by CI"
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

variable "web_subnet_cidrs" {
  type = list(string)
}

variable "app_subnet_cidrs" {
  type = list(string)
}

variable "db_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type = bool
}

variable "excluded_zone_ids" {
  description = "Availability Zone IDs the stack must not use"
  type        = list(string)
  default     = []
}

# --- DNS / TLS ---------------------------------------------------------------

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone (e.g. example.com). Empty = no domain yet: the app is served over plain HTTP on the load balancer's own address"
  type        = string
  default     = ""
}

variable "record_name" {
  description = "Subdomain for this environment (e.g. dev); used only when hosted_zone_name is set"
  type        = string
  default     = ""
}

# --- Compute -----------------------------------------------------------------

variable "app_port" {
  description = "Port the FastAPI backend listens on"
  type        = number
  default     = 8000
}

variable "web_instance_type" {
  type = string
}

variable "app_instance_type" {
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

# --- Protection and observability --------------------------------------------

variable "deletion_protection" {
  description = "Protect the ALBs and database from deletion and take a final DB snapshot (true for prod)"
  type        = bool
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
