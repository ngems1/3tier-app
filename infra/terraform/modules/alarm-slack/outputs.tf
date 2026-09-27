output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}
