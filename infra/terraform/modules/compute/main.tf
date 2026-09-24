# Launch templates and Auto Scaling Groups for the web and app tiers.
#
# Instances boot from immutable, versioned AMIs baked by Packer
# (deploy/ec2/packer). The release version is part of the launch template,
# so deploying a new version creates a new template version and the ASG
# performs a rolling instance refresh (launch new, wait healthy, then
# terminate old) with automatic rollback if the new instances fail.

locals {
  tiers = {
    web = {
      ami_id           = var.web_ami_id
      instance_type    = var.web_instance_type
      subnet_ids       = var.web_subnet_ids
      sg_id            = var.web_sg_id
      profile          = aws_iam_instance_profile.web.name
      target_group_arn = var.web_target_group_arn
      min_size         = var.web_min_size
      max_size         = var.web_max_size
      desired_capacity = var.web_desired_capacity
      user_data = templatefile("${path.module}/templates/web-user-data.sh.tftpl", {
        environment  = var.environment
        app_version  = var.app_version
        app_alb_dns  = var.app_alb_dns_name
        metrics_ns   = var.metrics_namespace
        web_log_grp  = var.web_log_group_name
        cw_agent_cfg = "/opt/three-tier/cloudwatch/web.json"
      })
    }
    app = {
      ami_id           = var.app_ami_id
      instance_type    = var.app_instance_type
      subnet_ids       = var.app_subnet_ids
      sg_id            = var.app_sg_id
      profile          = aws_iam_instance_profile.app.name
      target_group_arn = var.app_target_group_arn
      min_size         = var.app_min_size
      max_size         = var.app_max_size
      desired_capacity = var.app_desired_capacity
      user_data = templatefile("${path.module}/templates/app-user-data.sh.tftpl", {
        environment   = var.environment
        app_version   = var.app_version
        region        = local.region
        db_host       = var.db_host
        db_port       = var.db_port
        db_name       = var.db_name
        db_secret_arn = var.db_secret_arn
        metrics_ns    = var.metrics_namespace
        app_log_grp   = var.app_log_group_name
        cw_agent_cfg  = "/opt/three-tier/cloudwatch/app.json"
      })
    }
  }
}

resource "aws_launch_template" "this" {
  for_each = local.tiers

  name                   = "${var.name}-${each.key}"
  image_id               = each.value.ami_id
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [each.value.sg_id]
  user_data              = base64encode(each.value.user_data)
  update_default_version = true

  iam_instance_profile {
    name = each.value.profile
  }

  # IMDSv2 only, not reachable from containers/proxies on the host.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Encrypted root volume (KMS-backed, AWS managed key for EBS).
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.name}-${each.key}"
      Tier    = each.key
      Version = var.app_version
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.name}-${each.key}"
      Tier = each.key
    }
  }
}

resource "aws_autoscaling_group" "this" {
  for_each = local.tiers

  name                      = "${var.name}-${each.key}"
  vpc_zone_identifier       = each.value.subnet_ids
  min_size                  = each.value.min_size
  max_size                  = each.value.max_size
  desired_capacity          = each.value.desired_capacity
  target_group_arns         = [each.value.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  default_instance_warmup   = 120
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
      auto_rollback          = true
    }
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${var.name}-${each.key}"
    propagate_at_launch = true
  }

  lifecycle {
    # Scaling policies own desired capacity after the group is created.
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu" {
  for_each = local.tiers

  name                   = "${var.name}-${each.key}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.this[each.key].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}
