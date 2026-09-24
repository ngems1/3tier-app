output "web_alb_arn_suffix" {
  value = aws_lb.web.arn_suffix
}

output "web_alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "web_alb_zone_id" {
  value = aws_lb.web.zone_id
}

output "web_target_group_arn" {
  value = aws_lb_target_group.web.arn
}

output "web_target_group_arn_suffix" {
  value = aws_lb_target_group.web.arn_suffix
}

output "app_alb_arn_suffix" {
  value = aws_lb.app.arn_suffix
}

output "app_alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "app_target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "app_target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}
