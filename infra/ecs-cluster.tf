resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# Service discovery so the UI service can reach Carts by DNS name instead of
# a hardcoded IP or a second load balancer.
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "${var.project_name}.local"
  description = "Internal service discovery for ${var.project_name}"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "carts" {
  name = "carts"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "catalog" {
  name = "catalog"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "checkout" {
  name = "checkout"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
