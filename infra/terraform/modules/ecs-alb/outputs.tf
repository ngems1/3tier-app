output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.service : k => tg.arn }
}

output "target_group_arn_suffixes" {
  value = { for k, tg in aws_lb_target_group.service : k => tg.arn_suffix }
}

output "listener_rule_arns" {
  description = "Exposed so services can depend on routing being in place"
  value       = [for r in aws_lb_listener_rule.path : r.arn]
}
