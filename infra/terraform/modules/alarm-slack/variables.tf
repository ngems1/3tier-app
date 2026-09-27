variable "name" {
  description = "Name prefix of the environment, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "iam_name" {
  description = "Name prefix for IAM roles (must start with the prefix the account allows)"
  type        = string
}

variable "stack_label" {
  description = "Shown in Slack messages, e.g. \"EC2 prod\""
  type        = string
}

variable "sns_topic_arn" {
  description = "Alarm topic the function subscribes to"
  type        = string
}

variable "kms_key_arn" {
  description = "Environment KMS key, used to encrypt the function's log group"
  type        = string
}

variable "log_retention_days" {
  type = number
}

variable "webhook_parameter_name" {
  description = "SSM SecureString parameter holding the Slack webhook URL (written by the deploy pipeline)"
  type        = string
}
