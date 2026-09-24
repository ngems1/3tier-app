output "plan_role_arn" {
  description = "Set as GitHub repository variable AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "build_role_arn" {
  description = "Set as GitHub repository variable AWS_BUILD_ROLE_ARN"
  value       = aws_iam_role.build.arn
}

output "deploy_role_arns" {
  description = "Set each as the AWS_DEPLOY_ROLE_ARN variable of the matching GitHub Environment"
  value       = { for env, role in aws_iam_role.deploy : env => role.arn }
}

output "artifact_bucket" {
  description = "Set as GitHub repository variable ARTIFACT_BUCKET"
  value       = aws_s3_bucket.artifacts.bucket
}

output "ecr_registry" {
  description = "ECR registry host (the pipeline discovers it on login; shown for reference)"
  value       = split("/", values(aws_ecr_repository.app)[0].repository_url)[0]
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
