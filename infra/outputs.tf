output "alb_dns_name" {
  description = "Raw ALB DNS name (fallback if the custom domain isn't resolving yet)"
  value       = aws_lb.main.dns_name
}

output "site_url" {
  description = "Public URL for the UI service"
  value       = "https://${local.site_fqdn}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "carts_table_name" {
  value = aws_dynamodb_table.carts.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "github_actions_ecr_role_arn" {
  description = "Role ARN for the CI pipeline to configure in .github/workflows/pipeline.yml"
  value       = aws_iam_role.github_actions_ecr.arn
}

output "aurora_cluster_endpoint" {
  description = "Aurora writer endpoint - useful for manually verifying connectivity or the master secret during troubleshooting"
  value       = aws_rds_cluster.catalog.endpoint
}

output "aurora_master_secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret holding Aurora's master credentials. Retrieve the actual value only via `aws secretsmanager get-secret-value`, never printed here."
  value       = aws_rds_cluster.catalog.master_user_secret[0].secret_arn
}
