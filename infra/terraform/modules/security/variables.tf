variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to"
  type        = string
}

variable "app_port" {
  description = "Port the FastAPI backend listens on"
  type        = number
}
