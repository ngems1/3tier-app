variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-ecs-dev"
  type        = string
}

variable "iam_name" {
  description = "Name prefix for IAM roles"
  type        = string
}

variable "services" {
  description = "Containers to run. image should be pinned by digest (repo@sha256:...)."
  type = map(object({
    image          = string
    port           = number
    cpu            = number
    memory         = number
    desired_count  = number
    min_count      = number
    max_count      = number
    health_command = string
    readonly_root  = bool
    read_db_secret = bool
    environment    = map(string)
  }))
}

variable "subnet_ids" {
  description = "Private subnets per service"
  type        = map(list(string))
}

variable "security_group_ids" {
  description = "Security group per service"
  type        = map(string)
}

variable "target_group_arns" {
  description = "ALB target group per service"
  type        = map(string)
}

variable "routing_dependencies" {
  description = "ARNs of the ALB listener/rules; services are created after them"
  type        = list(string)
}

variable "db_secret_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "log_retention_days" {
  type = number
}

variable "cpu_target_percent" {
  type    = number
  default = 60
}
