terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27.0"
    }
  }

  # Stored next to the environment states, in the bucket created by
  # ../state-bucket (apply that folder first).
  backend "s3" {
    bucket       = "cloudbatch818-three-tier-tfstate-9ntql4o5"
    key          = "cloudbatch818-three-tier/bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloudbatch818-three-tier"
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
