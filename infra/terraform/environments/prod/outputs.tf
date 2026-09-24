output "app_url" {
  value = module.stack.app_url
}

output "deployed_version" {
  value = module.stack.deployed_version
}

output "web_asg_name" {
  value = module.stack.web_asg_name
}

output "app_asg_name" {
  value = module.stack.app_asg_name
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
