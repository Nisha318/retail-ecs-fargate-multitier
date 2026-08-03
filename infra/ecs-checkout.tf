resource "aws_ecs_task_definition" "checkout" {
  family                   = "${var.project_name}-checkout"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.checkout_task_execution.arn
  task_role_arn            = aws_iam_role.checkout_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "checkout"
      image     = "${aws_ecr_repository.checkout.repository_url}:${var.checkout_image_tag}"
      essential = true
      portMappings = [{
        containerPort = var.checkout_container_port
        protocol      = "tcp"
      }]
      # Config confirmed against Checkout's own README and source
      # (RedisCheckoutRepository.ts, app.controller.ts) - see
      # docs/DECISIONS.md ADR-009.
      #
      # RETAIL_CHECKOUT_ENDPOINTS_ORDERS intentionally left empty. This is
      # NOT the same situation as Phase 1's Carts/UI bug: this fallback is
      # explicitly documented in Checkout's own README ("If empty uses a
      # mock implementation"), not a silent, undocumented behavior
      # discovered only by reading source. Orders is not deployed yet in
      # this phase; wiring this up is deferred until Orders exists.
      environment = [
        {
          name  = "RETAIL_CHECKOUT_PERSISTENCE_PROVIDER"
          value = "redis"
        },
        {
          name  = "RETAIL_CHECKOUT_ENDPOINTS_ORDERS"
          value = ""
        }
      ]
      # Both values are full connection strings with the Redis AUTH token
      # already embedded (see elasticache.tf), not bare endpoints. ioredis
      # takes the entire URL as a single value, which is why these are
      # whole-secret references rather than JSON-key extractions like
      # Catalog's username/password pair.
      secrets = [
        {
          name      = "RETAIL_CHECKOUT_PERSISTENCE_REDIS_URL"
          valueFrom = aws_secretsmanager_secret.redis_writer_url.arn
        },
        {
          name      = "RETAIL_CHECKOUT_PERSISTENCE_REDIS_READER_URL"
          valueFrom = aws_secretsmanager_secret.redis_reader_url.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "checkout"
        }
      }
      # /health (confirmed via app.controller.ts, using @nestjs/terminus)
      # is LIVENESS ONLY - it checks a chaos-simulation indicator, not
      # Redis connectivity. A passing health check here does not confirm
      # Redis is reachable; that requires a separate, deliberate
      # verification step after deploy (see ADR-009), the same way
      # Carts' DynamoDB writes were verified directly rather than trusted
      # from a green health check alone.
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.checkout_container_port}/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-checkout-taskdef"
  }
}

resource "aws_ecs_service" "checkout" {
  name            = "checkout"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.checkout.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.checkout_task.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.checkout.arn
  }

  tags = {
    Name = "${var.project_name}-checkout-service"
  }
}
