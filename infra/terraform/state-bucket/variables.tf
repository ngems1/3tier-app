variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  description = "Globally unique name of the Terraform state bucket (must match the backend blocks)"
  type        = string
  default     = "cloudbatch818-three-tier-tfstate-seb"
}
