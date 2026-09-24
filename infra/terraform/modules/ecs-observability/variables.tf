variable "name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "alarm_emails" {
  type    = list(string)
  default = []
}

variable "cluster_name" {
  type = string
}

variable "services" {
  description = "Per service: ECS service name, minimum task count and target group ARN suffix"
  type = map(object({
    service_name = string
    min_count    = number
    tg_suffix    = string
  }))
}

variable "alb_arn_suffix" {
  type = string
}

variable "db_instance_id" {
  type = string
}

variable "cpu_alarm_percent" {
  type    = number
  default = 80
}

variable "memory_alarm_percent" {
  type    = number
  default = 85
}

variable "target_5xx_threshold" {
  type    = number
  default = 5
}

variable "latency_p95_threshold_seconds" {
  type    = number
  default = 1
}
