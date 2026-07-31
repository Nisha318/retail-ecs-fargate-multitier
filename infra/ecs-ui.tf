resource "aws_ecs_task_definition" "ui" {
  family                   = "${var.project_name}-ui"
  requires_compatibilities = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = "512"
  memory                    = "1024"
  execution_role_arn        = aws_iam_role.task_execution.arn
  task_role_arn             = aws_iam_role.ui_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "ui"
      image     = var.ui_image
      essential = true
      portMappings = [{
        containerPort = var.ui_container_port
        protocol      = "tcp"
      }]
      # NOTE: UI expects a Catalog endpoint too. Not deployed in Phase 1 —
      # catalog-dependent pages will error until Phase 2. See
      # docs/architecture.md open items before treating this as a bug.
      environment = [
        {
          name  = "RETAIL_CARTS_ENDPOINT"
          value = "http://carts.${var.project_name}.local:${var.carts_container_port}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ui"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.ui_container_port}/actuator/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-ui-taskdef"
  }
}

resource "aws_ecs_service" "ui" {
  name            = "ui"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ui.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ui_task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui.arn
    container_name    = "ui"
    container_port    = var.ui_container_port
  }

  health_check_grace_period_seconds = 30

  depends_on = [aws_lb_listener.https, aws_lb_listener.http_redirect]

  tags = {
    Name = "${var.project_name}-ui-service"
  }
}
