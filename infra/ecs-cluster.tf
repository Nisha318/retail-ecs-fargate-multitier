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

resource "aws_security_group" "ui_task" {
  name        = "${var.project_name}-ui-task"
  description = "UI Fargate task security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = var.ui_container_port
    to_port         = var.ui_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ui-task-sg"
  }
}

resource "aws_security_group" "carts_task" {
  name        = "${var.project_name}-carts-task"
  description = "Carts Fargate task security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From UI service"
    from_port       = var.carts_container_port
    to_port         = var.carts_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ui_task.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-carts-task-sg"
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
