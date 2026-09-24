output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "log_group_names" {
  value = { for k, g in aws_cloudwatch_log_group.tier : k => g.name }
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}
