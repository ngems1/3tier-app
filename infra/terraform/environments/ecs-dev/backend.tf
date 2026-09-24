# Remote state: encrypted, versioned S3 bucket (created by
# infra/terraform/state-bucket) with native S3 state locking. Each
# environment has its own state file.
terraform {
  backend "s3" {
    bucket       = "cloudbatch818-three-tier-tfstate-9ntql4o5"
    key          = "cloudbatch818-three-tier-ecs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
