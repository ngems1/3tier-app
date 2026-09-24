variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "environment" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "log_retention_days" {
  description = "Retention for application log groups"
  type        = number
}

variable "alarm_emails" {
  description = "Email addresses subscribed to alarm notifications (each must confirm the subscription)"
  type        = list(string)
  default     = []
}

variable "metrics_namespace" {
  description = "CloudWatch Agent namespace (memory and disk metrics)"
  type        = string
}

variable "web_alb_arn_suffix" {
  type = string
}

variable "web_target_group_arn_suffix" {
  type = string
}

variable "app_alb_arn_suffix" {
  type = string
}

variable "app_target_group_arn_suffix" {
  type = string
}

variable "web_asg_name" {
  type = string
}

variable "app_asg_name" {
  type = string
}

variable "web_min_size" {
  type = number
}

variable "app_min_size" {
  type = number
}

variable "db_instance_id" {
  type = string
}

variable "target_5xx_threshold" {
  description = "5XX responses per minute that trigger an alarm"
  type        = number
  default     = 5
}

variable "latency_p95_threshold_seconds" {
  type    = number
  default = 1
}

variable "cpu_alarm_percent" {
  type    = number
  default = 80
}

variable "memory_alarm_percent" {
  type    = number
  default = 85
}

variable "rds_cpu_alarm_percent" {
  type    = number
  default = 80
}

variable "rds_free_storage_bytes" {
  description = "Alarm when free storage falls below this many bytes"
  type        = number
  default     = 5368709120
}

variable "rds_freeable_memory_bytes" {
  description = "Alarm when freeable memory falls below this many bytes"
  type        = number
  default     = 268435456
}

variable "rds_max_connections" {
  type    = number
  default = 100
}
