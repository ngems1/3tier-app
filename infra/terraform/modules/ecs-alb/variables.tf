variable "name" {
  description = "Name prefix for the logs bucket, WAF and tags, e.g. cloudbatch818-three-tier-ecs-dev"
  type        = string
}

variable "short_name" {
  description = "Short prefix for the load balancer and target group names (AWS limits them to 32 characters), e.g. cloudbatch818-ecs-dev"
  type        = string

  validation {
    # Target groups are <short_name>-<service>; "-frontend" is 9 characters.
    condition     = length(var.short_name) <= 23
    error_message = "short_name must be 23 characters or fewer (load balancer and target group names are limited to 32)."
  }
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "services" {
  description = "Target groups to create. path_patterns routes those paths to the service; the default_service gets everything else."
  type = map(object({
    port              = number
    health_check_path = string
    path_patterns     = list(string)
    priority          = number
  }))
}

variable "default_service" {
  description = "Service that receives requests not matched by any path pattern"
  type        = string
}

variable "enable_https" {
  description = "Serve HTTPS with certificate_arn (and redirect HTTP). False = temporary HTTP-only mode without a domain"
  type        = bool
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "deletion_protection" {
  type = bool
}

variable "kms_key_arn" {
  description = "KMS key for the WAF log group"
  type        = string
}

variable "log_retention_days" {
  type = number
}

variable "access_log_retention_days" {
  type    = number
  default = 90
}

variable "force_destroy_logs" {
  type    = bool
  default = false
}
