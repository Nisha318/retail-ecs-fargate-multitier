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
