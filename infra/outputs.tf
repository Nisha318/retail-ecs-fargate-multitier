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
