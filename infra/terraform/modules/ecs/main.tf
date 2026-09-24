# ECS on Fargate: one cluster, and one task definition + service per
# container (frontend, backend). Images are pinned by digest, so a task
# definition always runs exactly the image that was built and scanned.
#
# Deployments are rolling (new tasks start and pass ALB health checks before
# old ones stop) with the ECS deployment circuit breaker: if new tasks keep
# failing, ECS stops the deployment and rolls back automatically.

data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition
}

# Makes the services wait for the load balancer routing to exist.
resource "terraform_data" "routing_ready" {
  input = var.routing_dependencies
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "service" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment decision set through log_retention_days (365 days in prod).
  for_each          = var.services
  name              = "/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# IAM: one execution role (pull images, write logs) and one task role per
# service (what the application itself may call).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.iam_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  for_each           = var.services
  name               = "${var.iam_name}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "db_secret" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid       = "DecryptDatabaseSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "db_secret" {
  for_each = { for k, s in var.services : k => s if s.read_db_secret }
  name     = "read-db-secret"
  role     = aws_iam_role.task[each.key].id
  policy   = data.aws_iam_policy_document.db_secret.json
}

# ---------------------------------------------------------------------------
# Task definitions and services
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "service" {
  #checkov:skip=CKV_AWS_336:The frontend Nginx image renders its config at startup and needs a writable filesystem; the backend runs read-only (see readonly_root per service).
  for_each = var.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = each.key
      image                  = each.value.image
      essential              = true
      readonlyRootFilesystem = each.value.readonly_root
      portMappings = [
        { containerPort = each.value.port, protocol = "tcp" }
      ]
      environment = [for k in sort(keys(each.value.environment)) : { name = k, value = each.value.environment[k] }]
      healthCheck = {
        command     = ["CMD-SHELL", each.value.health_command]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service[each.key].name
          awslogs-region        = local.region
          awslogs-stream-prefix = each.key
        }
      }
    }
  ])
}

resource "aws_ecs_service" "service" {
  for_each = var.services

  name                              = "${var.name}-${each.key}"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.service[each.key].arn
  desired_count                     = each.value.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 60
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids[each.key]
    security_groups  = [var.security_group_ids[each.key]]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arns[each.key]
    container_name   = each.key
    container_port   = each.value.port
  }

  lifecycle {
    # Auto scaling owns the running task count after creation.
    ignore_changes = [desired_count]
  }

  # Tasks must be able to pull images and read the DB secret from the first
  # start, or early failures would count against the circuit breaker.
  depends_on = [terraform_data.routing_ready, aws_iam_role_policy_attachment.execution, aws_iam_role_policy.db_secret]
}

# ---------------------------------------------------------------------------
# Auto scaling (target tracking on average CPU)
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "service" {
  for_each           = var.services
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.service[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.min_count
  max_capacity       = each.value.max_count
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each           = var.services
  name               = "${var.name}-${each.key}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.service[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
