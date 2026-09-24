output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_names" {
  value = { for k, s in aws_ecs_service.service : k => s.name }
}

output "log_group_names" {
  value = { for k, g in aws_cloudwatch_log_group.service : k => g.name }
}

output "task_definition_arns" {
  value = { for k, t in aws_ecs_task_definition.service : k => t.arn }
}

output "iam_names" {
  value = concat([aws_iam_role.execution.name], [for r in aws_iam_role.task : r.name])
}

output "controls" {
  description = "Deployment and network settings per service (checked by the tests)"
  value = {
    for k, s in aws_ecs_service.service : k => {
      circuit_breaker_rollback = s.deployment_circuit_breaker[0].enable && s.deployment_circuit_breaker[0].rollback
      min_healthy_percent      = s.deployment_minimum_healthy_percent
      public_ip                = s.network_configuration[0].assign_public_ip
      container_insights       = one([for st in aws_ecs_cluster.this.setting : st.value if st.name == "containerInsights"])
    }
  }
}
