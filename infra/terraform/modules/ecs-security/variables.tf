variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-ecs-dev"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "frontend_port" {
  type = number
}

variable "backend_port" {
  type = number
}
