output "app_url" {
  value = local.use_domain ? "https://${module.dns[0].fqdn}" : "http://${module.alb.web_alb_dns_name}"
}

output "deployed_version" {
  value = var.app_version
}

output "web_asg_name" {
  value = module.compute.web_asg_name
}

output "app_asg_name" {
  value = module.compute.app_asg_name
}

output "db_endpoint" {
  value = module.database.address
}

output "db_secret_arn" {
  value = module.database.master_user_secret_arn
}

output "alarm_topic_arn" {
  value = module.observability.sns_topic_arn
}

output "dashboard_name" {
  value = module.observability.dashboard_name
}
