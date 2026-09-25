variable "name" {
  description = "Name prefix, e.g. cloudbatch818-three-tier-dev"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC to create (ignored when existing_vpc_id is set)"
  type        = string
}

variable "existing_vpc_id" {
  description = "Build the subnets inside this existing VPC instead of creating a VPC (e.g. when the account's VPC quota is full). The VPC must have an internet gateway, and the subnet CIDRs must be free ranges inside it. Empty = create a VPC."
  type        = string
  default     = ""

  validation {
    condition     = var.existing_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.existing_vpc_id))
    error_message = "existing_vpc_id must be empty or a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnets (ALB, NAT), one per AZ"
  type        = list(string)
}

variable "web_subnet_cidrs" {
  description = "Private web-tier subnets, one per AZ"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "Private app-tier subnets, one per AZ"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Isolated database subnets, one per AZ"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper, dev) instead of one per AZ (highly available, prod)"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs"
  type        = number
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the flow log group"
  type        = string
}

variable "excluded_zone_ids" {
  description = "Availability Zone IDs to skip (e.g. use1-az3, which lacks many current instance types)"
  type        = list(string)
  default     = []
}

variable "iam_name" {
  description = "Name prefix for IAM roles, policies and instance profiles, e.g. cloudbatch818-three-tier-dev"
  type        = string
}
