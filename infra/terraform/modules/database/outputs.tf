output "instance_id" {
  value = aws_db_instance.this.identifier
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
