output "app_url" {
  value = module.stack.app_url
}

output "deployed_version" {
  value = module.stack.deployed_version
}

output "cluster_name" {
  value = module.stack.cluster_name
}

output "service_names" {
  value = module.stack.service_names
}

output "task_definition_arns" {
  value = module.stack.task_definition_arns
}

output "images" {
  value = module.stack.images
}

output "db_endpoint" {
  value = module.stack.db_endpoint
}

output "db_secret_arn" {
  value = module.stack.db_secret_arn
}

output "alarm_topic_arn" {
  value = module.stack.alarm_topic_arn
}

output "dashboard_name" {
  value = module.stack.dashboard_name
}
