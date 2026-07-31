resource "aws_ecs_task_definition" "carts" {
  family                   = "${var.project_name}-carts"
  requires_compatibilities = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = "512"
  memory                    = "1024"
  execution_role_arn        = aws_iam_role.task_execution.arn
  task_role_arn             = aws_iam_role.carts_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "carts"
      image     = var.carts_image
      essential = true
      portMappings = [{
        containerPort = var.carts_container_port
        protocol      = "tcp"
      }]
      # Confirmed against AWS's own EKS Workshop ConfigMap reference for this
      # exact service (eksworkshop.com/docs/security/iam-roles-for-service-accounts/using-dynamo).
      # RETAIL_CART_PERSISTENCE_DYNAMODB_ENDPOINT is intentionally omitted -
      # without it, the SDK defaults to real AWS DynamoDB instead of a local
      # test instance. No static AWS_ACCESS_KEY_ID/SECRET - credentials come
      # from the carts task role instead.
      environment = [
        {
          name  = "RETAIL_CART_PERSISTENCE_PROVIDER"
          value = "dynamodb"
        },
        {
          name  = "RETAIL_CART_PERSISTENCE_DYNAMODB_TABLE_NAME"
          value = aws_dynamodb_table.carts.name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "carts"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.carts_container_port}/actuator/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-carts-taskdef"
  }
}

resource "aws_ecs_service" "carts" {
  name            = "carts"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.carts.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.carts_task.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.carts.arn
  }

  tags = {
    Name = "${var.project_name}-carts-service"
  }
}
