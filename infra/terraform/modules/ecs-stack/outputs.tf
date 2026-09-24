output "app_url" {
  value = local.use_domain ? "https://${module.dns[0].fqdn}" : "http://${module.alb.alb_dns_name}"
}

output "deployed_version" {
  value = var.app_version
}

output "cluster_name" {
  value = module.ecs.cluster_name
}

output "service_names" {
  value = module.ecs.service_names
}

output "task_definition_arns" {
  description = "Task definition each service must be running once the deployment finishes"
  value       = module.ecs.task_definition_arns
}

output "images" {
  description = "Images (pinned by digest) running in this environment"
  value       = local.images
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

output "iam_names" {
  value = module.ecs.iam_names
}
