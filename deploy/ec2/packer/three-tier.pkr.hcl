# Immutable release images for the EC2 deployment.
#
# CI bakes one web AMI and one app AMI per git commit. Each image contains
# the application release (React build or FastAPI code + pinned
# dependencies) on a patched, hardened Amazon Linux 2023 base, and is tagged
# with Version=<commit SHA>. Terraform selects AMIs by that tag, so a deploy
# or rollback is just "use the AMIs for version X".
#
#   packer init  deploy/ec2/packer
#   packer build -var app_version=$(git rev-parse HEAD) -only 'amazon-ebs.app' deploy/ec2/packer
#   packer build -var app_version=$(git rev-parse HEAD) -only 'amazon-ebs.web' deploy/ec2/packer
#
# The web image expects app/frontend/build to exist (npm run build).

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.8"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "app_version" {
  type        = string
  description = "Git commit SHA of the release being baked"

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.app_version))
    error_message = "The app_version must be a git commit SHA."
  }
}

variable "project" {
  type        = string
  default     = "cloudbatch818-three-tier"
  description = "Name prefix for the AMIs and value of their Project tag (must match var.project in Terraform)"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Public subnet for the temporary build instance (empty = default VPC)"
}

locals {
  repo_root  = "${path.root}/../../.."
  build_date = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())

  common_tags = {
    Project   = var.project
    Version   = var.app_version
    BuildDate = local.build_date
    BuiltBy   = "packer"
    BaseImage = "{{ .SourceAMIName }}"
  }
}

source "amazon-ebs" "base" {
  region        = var.aws_region
  instance_type = var.instance_type
  subnet_id     = var.subnet_id == "" ? null : var.subnet_id

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      architecture        = "x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ssh_username                              = "ec2-user"
  associate_public_ip_address               = true
  temporary_security_group_source_public_ip = true

  # Encrypted image snapshots; IMDSv2 on the build instance too.
  encrypt_boot = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  source "amazon-ebs.base" {
    name     = "app"
    ami_name = "${var.project}-app-${var.app_version}-{{timestamp}}"
    tags     = merge(local.common_tags, { Name = "${var.project}-app-${var.app_version}", Component = "app" })
    snapshot_tags = {
      Project   = var.project
      Component = "app"
      Version   = var.app_version
    }
  }

  source "amazon-ebs.base" {
    name     = "web"
    ami_name = "${var.project}-web-${var.app_version}-{{timestamp}}"
    tags     = merge(local.common_tags, { Name = "${var.project}-web-${var.app_version}", Component = "web" })
    snapshot_tags = {
      Project   = var.project
      Component = "web"
      Version   = var.app_version
    }
  }

  provisioner "shell" {
    inline = ["mkdir -p /tmp/build/release"]
  }

  # Shared hardening and helper scripts
  provisioner "file" {
    source      = "${path.root}/../common/"
    destination = "/tmp/build"
  }

  # Tier-specific release content
  provisioner "file" {
    only        = ["amazon-ebs.app"]
    sources     = ["${path.root}/../app/", "${local.repo_root}/app/backend/requirements.txt"]
    destination = "/tmp/build/"
  }

  provisioner "file" {
    only        = ["amazon-ebs.app"]
    source      = "${local.repo_root}/app/backend/app"
    destination = "/tmp/build/release/"
  }

  provisioner "file" {
    only        = ["amazon-ebs.web"]
    source      = "${path.root}/../web/"
    destination = "/tmp/build"
  }

  provisioner "file" {
    only        = ["amazon-ebs.web"]
    source      = "${local.repo_root}/app/frontend/build/"
    destination = "/tmp/build/release"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo env {{ .Vars }} bash '{{ .Path }}'"
    environment_vars = [
      "APP_VERSION=${var.app_version}",
      "TIER=${source.name}",
    ]
    inline = [
      "set -euo pipefail",
      "bash /tmp/build/harden.sh",
      "bash /tmp/build/provision-$TIER.sh",
      "bash /tmp/build/finalize.sh",
    ]
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
    custom_data = {
      version = var.app_version
    }
  }
}
