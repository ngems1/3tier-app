variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes"
  type        = number
  default     = 30
}
