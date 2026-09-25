terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "cloudbatch818-three-tier"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "3tier-app"
    }
  }
}
