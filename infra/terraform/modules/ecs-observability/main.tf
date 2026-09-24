# Alarms and dashboard for the ECS project: service health and task count,
# CPU and memory per service, ALB errors and latency, and RDS.

data "aws_region" "current" {}

locals {
  region        = data.aws_region.current.region
  alarm_actions = [aws_sns_topic.alarms.arn]
  services      = var.services # key => { service_name, min_count, tg_suffix }
}

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alarm_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- ECS service health ------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-running-tasks-low"
  alarm_description   = "${each.key}: fewer running tasks than the minimum (tasks crashing or failing health checks)"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.min_count
  treat_missing_data  = "breaching"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = each.value.service_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-cpu-high"
  alarm_description   = "${each.key}: average CPU above ${var.cpu_alarm_percent}% (auto scaling may be at its maximum)"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_percent
  dimensions          = { ClusterName = var.cluster_name, ServiceName = each.value.service_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-memory-high"
  alarm_description   = "${each.key}: average memory above ${var.memory_alarm_percent}%"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_alarm_percent
  dimensions          = { ClusterName = var.cluster_name, ServiceName = each.value.service_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Load balancer -----------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-no-healthy-targets"
  alarm_description   = "${each.key}: no healthy targets behind the ALB (outage)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-5xx"
  alarm_description   = "${each.key}: targets returning HTTP 5XX errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.target_5xx_threshold
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  for_each            = local.services
  alarm_name          = "${var.name}-${each.key}-latency-p95"
  alarm_description   = "${each.key}: p95 response time above ${var.latency_p95_threshold_seconds}s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p95_threshold_seconds
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-elb-5xx"
  alarm_description   = "ALB itself returning 5XX (no healthy targets, timeouts)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.target_5xx_threshold
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- RDS -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds" {
  for_each = {
    cpu-high            = { metric = "CPUUtilization", op = "GreaterThanThreshold", threshold = 80, desc = "RDS CPU above 80%" }
    free-storage-low    = { metric = "FreeStorageSpace", op = "LessThanThreshold", threshold = 5368709120, desc = "RDS free storage below 5 GiB" }
    freeable-memory-low = { metric = "FreeableMemory", op = "LessThanThreshold", threshold = 268435456, desc = "RDS freeable memory below 256 MiB" }
    connections-high    = { metric = "DatabaseConnections", op = "GreaterThanThreshold", threshold = 100, desc = "RDS connections above 100" }
  }

  alarm_name          = "${var.name}-rds-${each.key}"
  alarm_description   = each.value.desc
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = each.value.op
  threshold           = each.value.threshold
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Dashboard -----------------------------------------------------------------

locals {
  alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.running_tasks_low : a.arn],
    [for a in aws_cloudwatch_metric_alarm.no_healthy_targets : a.arn],
    [for a in aws_cloudwatch_metric_alarm.target_5xx : a.arn],
    [for a in aws_cloudwatch_metric_alarm.latency_p95 : a.arn],
    [aws_cloudwatch_metric_alarm.alb_5xx.arn],
    [for a in aws_cloudwatch_metric_alarm.cpu_high : a.arn],
    [for a in aws_cloudwatch_metric_alarm.memory_high : a.arn],
    [for a in aws_cloudwatch_metric_alarm.rds : a.arn],
  )

  widgets = [
    {
      type       = "alarm", x = 0, y = 0, width = 24, height = 4
      properties = { title = "Alarm status", alarms = local.alarm_arns }
    },
    {
      type = "metric", x = 0, y = 4, width = 8, height = 6
      properties = {
        title   = "Running tasks", region = local.region, view = "timeSeries", stat = "Minimum", period = 60
        metrics = [for k, s in local.services : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s.service_name, { label = k }]]
      }
    },
    {
      type = "metric", x = 8, y = 4, width = 8, height = 6
      properties = {
        title   = "Service CPU %", region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [for k, s in local.services : ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", s.service_name, { label = k }]]
      }
    },
    {
      type = "metric", x = 16, y = 4, width = 8, height = 6
      properties = {
        title   = "Service memory %", region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [for k, s in local.services : ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", s.service_name, { label = k }]]
      }
    },
    {
      type = "metric", x = 0, y = 10, width = 12, height = 6
      properties = {
        title = "Requests and 5XX", region = local.region, view = "timeSeries", stat = "Sum", period = 60
        metrics = concat(
          [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "requests" }]],
          [["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "ALB 5XX" }]],
          [for k, s in local.services : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", s.tg_suffix, { label = "${k} 5XX" }]],
        )
      }
    },
    {
      type = "metric", x = 12, y = 10, width = 12, height = 6
      properties = {
        title   = "Latency p95 (seconds)", region = local.region, view = "timeSeries", stat = "p95", period = 60
        metrics = [for k, s in local.services : ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", s.tg_suffix, { label = k }]]
      }
    },
    {
      type = "metric", x = 0, y = 16, width = 12, height = 6
      properties = {
        title = "RDS CPU % and connections", region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { label = "CPU %" }],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { label = "connections", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 16, width = 12, height = 6
      properties = {
        title = "RDS free storage and memory (bytes)", region = local.region, view = "timeSeries", stat = "Average", period = 300
        metrics = [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id, { label = "free storage" }],
          ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_instance_id, { label = "freeable memory" }],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = local.widgets })
}
