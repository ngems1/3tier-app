output "web_asg_name" {
  value = aws_autoscaling_group.this["web"].name
}

output "app_asg_name" {
  value = aws_autoscaling_group.this["app"].name
}

output "web_role_arn" {
  value = aws_iam_role.web.arn
}

output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "launch_templates" {
  description = "Security-relevant launch template settings (used by tests)"
  value = {
    for tier, lt in aws_launch_template.this : tier => {
      encrypted_root = lt.block_device_mappings[0].ebs[0].encrypted == "true"
      imdsv2         = lt.metadata_options[0].http_tokens == "required"
    }
  }
}

output "iam_names" {
  description = "Names of the IAM roles, policy and instance profiles created for the instances"
  value = [
    aws_iam_role.web.name,
    aws_iam_role.app.name,
    aws_iam_policy.cloudwatch_agent.name,
    aws_iam_instance_profile.web.name,
    aws_iam_instance_profile.app.name,
  ]
}
