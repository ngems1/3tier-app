variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "short_name" {
  description = "Short name prefix for the load balancers and target groups, whose names are limited to 32 characters, e.g. cloudbatch818-3t-dev"
  type        = string

  validation {
    condition     = length(var.short_name) <= 28
    error_message = "short_name must be 28 characters or fewer (ALB and target group names are limited to 32)."
  }
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "alb_public_sg_id" {
  type = string
}

variable "app_alb_sg_id" {
  type = string
}

variable "app_port" {
  type = number
}

variable "enable_https" {
  description = "Serve HTTPS with certificate_arn (and redirect HTTP). False = temporary HTTP-only mode without a domain"
  type        = bool
}

variable "certificate_arn" {
  description = "Validated ACM certificate for the public HTTPS listener (required when enable_https = true)"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the load balancers from accidental deletion"
  type        = bool
}

variable "kms_key_arn" {
  description = "KMS key for the WAF log group"
  type        = string
}

variable "log_retention_days" {
  type = number
}

variable "access_log_retention_days" {
  description = "Days to keep ALB access logs in S3"
  type        = number
  default     = 90
}

variable "force_destroy_logs" {
  description = "Allow terraform destroy to delete the access log bucket even if it contains logs (dev only)"
  type        = bool
  default     = false
}
