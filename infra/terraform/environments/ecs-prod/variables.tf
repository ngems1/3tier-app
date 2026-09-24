variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_version" {
  description = "Git commit SHA to deploy (its images must already be in ECR). Passed by CI: -var app_version=<sha>"
  type        = string
}

variable "alarm_emails" {
  description = "Emails that receive alarm notifications"
  type        = list(string)
  default     = []
}

variable "allow_destroy" {
  description = "Set to true only by the Destroy workflow (removes deletion protection before destroying)"
  type        = bool
  default     = false
}
