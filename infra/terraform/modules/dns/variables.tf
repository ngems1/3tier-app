variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone, e.g. ngems.xyz"
  type        = string
}

variable "record_name" {
  description = "Subdomain for this environment, e.g. dev"
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}
