output "vpc_id" {
  value = local.vpc_id
}

output "vpc_cidr_block" {
  value = local.vpc_cidr_block
}

output "uses_existing_vpc" {
  value = !local.create_vpc
}

output "flow_log_count" {
  value = length(aws_flow_log.this) + length(aws_flow_log.subnets)
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "web_subnet_ids" {
  value = aws_subnet.web[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}

output "nat_gateway_count" {
  value = length(aws_nat_gateway.this)
}
