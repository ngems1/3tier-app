# Logs, alarms and dashboard for one environment:
#   * encrypted log groups with defined retention for the web and app tiers
#   * an encrypted SNS topic every alarm notifies
#   * alarms for ALB health/errors/latency, EC2/ASG CPU, memory and
#     capacity, and RDS CPU/memory/storage/connections
#   * a single dashboard covering all of the above

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  tiers = {
    web = {
      alb_suffix = var.web_alb_arn_suffix
      tg_suffix  = var.web_target_group_arn_suffix
      asg_name   = var.web_asg_name
      min_size   = var.web_min_size
    }
    app = {
      alb_suffix = var.app_alb_arn_suffix
      tg_suffix  = var.app_target_group_arn_suffix
      asg_name   = var.app_asg_name
      min_size   = var.app_min_size
    }
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Log groups (written by the CloudWatch Agent on each instance)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "tier" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment decision set through log_retention_days (365 days in prod).
  for_each          = toset(["web", "app"])
  name              = "/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# Load balancer / target group alarms (both tiers)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-unhealthy-hosts"
  alarm_description   = "${each.key} target group has unhealthy targets"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = each.value.alb_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-no-healthy-hosts"
  alarm_description   = "${each.key} target group has no healthy targets (outage)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  dimensions          = { LoadBalancer = each.value.alb_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-5xx"
  alarm_description   = "${each.key} targets returning HTTP 5XX errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.target_5xx_threshold
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = each.value.alb_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-latency-p95"
  alarm_description   = "${each.key} p95 response time above ${var.latency_p95_threshold_seconds}s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latency_p95_threshold_seconds
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = each.value.alb_suffix, TargetGroup = each.value.tg_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "web_alb_5xx" {
  alarm_name          = "${var.name}-web-alb-elb-5xx"
  alarm_description   = "Public ALB itself returning 5XX (no healthy targets, timeouts)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.target_5xx_threshold
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = var.web_alb_arn_suffix }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------------------
# EC2 / Auto Scaling alarms (both tiers)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-cpu-high"
  alarm_description   = "${each.key} ASG average CPU above ${var.cpu_alarm_percent}% (scaling may be maxed out)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_percent
  dimensions          = { AutoScalingGroupName = each.value.asg_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-memory-high"
  alarm_description   = "${each.key} ASG memory use above ${var.memory_alarm_percent}% (CloudWatch Agent metric)"
  namespace           = var.metrics_namespace
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_alarm_percent
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = each.value.asg_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "capacity_low" {
  for_each            = local.tiers
  alarm_name          = "${var.name}-${each.key}-capacity-below-min"
  alarm_description   = "${each.key} ASG has fewer in-service instances than its minimum"
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 10
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.min_size
  dimensions          = { AutoScalingGroupName = each.value.asg_name }
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------------------
# RDS alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds" {
  for_each = {
    cpu-high = {
      metric = "CPUUtilization", op = "GreaterThanThreshold", threshold = var.rds_cpu_alarm_percent
      desc   = "RDS CPU above ${var.rds_cpu_alarm_percent}%"
    }
    free-storage-low = {
      metric = "FreeStorageSpace", op = "LessThanThreshold", threshold = var.rds_free_storage_bytes
      desc   = "RDS free storage below threshold"
    }
    freeable-memory-low = {
      metric = "FreeableMemory", op = "LessThanThreshold", threshold = var.rds_freeable_memory_bytes
      desc   = "RDS freeable memory below threshold"
    }
    connections-high = {
      metric = "DatabaseConnections", op = "GreaterThanThreshold", threshold = var.rds_max_connections
      desc   = "RDS connections above ${var.rds_max_connections}"
    }
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

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

locals {
  alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.no_healthy_hosts : a.arn],
    [for a in aws_cloudwatch_metric_alarm.unhealthy_hosts : a.arn],
    [for a in aws_cloudwatch_metric_alarm.target_5xx : a.arn],
    [for a in aws_cloudwatch_metric_alarm.latency_p95 : a.arn],
    [aws_cloudwatch_metric_alarm.web_alb_5xx.arn],
    [for a in aws_cloudwatch_metric_alarm.cpu_high : a.arn],
    [for a in aws_cloudwatch_metric_alarm.memory_high : a.arn],
    [for a in aws_cloudwatch_metric_alarm.capacity_low : a.arn],
    [for a in aws_cloudwatch_metric_alarm.rds : a.arn],
  )

  widgets = [
    {
      type       = "alarm", x = 0, y = 0, width = 24, height = 4
      properties = { title = "Alarm status", alarms = local.alarm_arns }
    },
    {
      type = "metric", x = 0, y = 4, width = 12, height = 6
      properties = {
        title = "Requests and 5XX errors", region = local.region, view = "timeSeries", stat = "Sum", period = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.web_alb_arn_suffix, { label = "web requests" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.web_alb_arn_suffix, "TargetGroup", var.web_target_group_arn_suffix, { label = "web 5XX" }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.web_alb_arn_suffix, { label = "web ALB 5XX" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.app_alb_arn_suffix, "TargetGroup", var.app_target_group_arn_suffix, { label = "app 5XX" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 4, width = 12, height = 6
      properties = {
        title = "Latency p95 (seconds)", region = local.region, view = "timeSeries", stat = "p95", period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.web_alb_arn_suffix, "TargetGroup", var.web_target_group_arn_suffix, { label = "web" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.app_alb_arn_suffix, "TargetGroup", var.app_target_group_arn_suffix, { label = "app" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 10, width = 8, height = 6
      properties = {
        title = "EC2 CPU % (ASG average)", region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.web_asg_name, { label = "web" }],
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.app_asg_name, { label = "app" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 10, width = 8, height = 6
      properties = {
        title = "EC2 memory % (ASG average)", region = local.region, view = "timeSeries", stat = "Average", period = 60
        metrics = [
          [var.metrics_namespace, "mem_used_percent", "AutoScalingGroupName", var.web_asg_name, { label = "web" }],
          [var.metrics_namespace, "mem_used_percent", "AutoScalingGroupName", var.app_asg_name, { label = "app" }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 10, width = 8, height = 6
      properties = {
        title = "ASG in-service / healthy targets", region = local.region, view = "timeSeries", stat = "Minimum", period = 60
        metrics = [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.web_asg_name, { label = "web in service" }],
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.app_asg_name, { label = "app in service" }],
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.web_alb_arn_suffix, "TargetGroup", var.web_target_group_arn_suffix, { label = "web healthy" }],
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.app_alb_arn_suffix, "TargetGroup", var.app_target_group_arn_suffix, { label = "app healthy" }],
        ]
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
