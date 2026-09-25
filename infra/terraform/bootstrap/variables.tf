variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  description = "Prefix for every resource name; must match var.project in modules/app-stack"
  type        = string
  default     = "cloudbatch818-three-tier"
}

variable "container_images" {
  description = "One ECR repository is created per image, named <project>-<image>"
  type        = list(string)
  default     = ["frontend", "backend"]
}

variable "images_to_keep" {
  description = "Number of release images kept per ECR repository (older ones expire)"
  type        = number
  default     = 50
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name"
  type        = string
  default     = "ngems1/3tier-app"
}

variable "github_repository_with_ids" {
  description = <<-EOT
    The same repository in GitHub's ID-based format, owner@ownerID/name@repoID.
    GitHub sends the OIDC "sub" claim in this format for this repository, e.g.
    repo:ngems1@330211773/3tier-app@1385421481:environment:dev. Both formats
    are accepted, so the roles keep working either way. Set to "" to accept only
    the name-based format.
  EOT
  type        = string
  default     = "ngems1@330211773/3tier-app@1385421481"
}

variable "environments" {
  description = "Deployment environments; each gets its own deploy role bound to the matching GitHub Environment"
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider (set false if the account already has one)"
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "S3 bucket that holds Terraform state"
  type        = string
  default     = "cloudbatch818-three-tier-tfstate-seb"
}

