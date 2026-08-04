resource "aws_ecs_task_definition" "catalog" {
  family                   = "${var.project_name}-catalog"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.catalog_task_execution.arn
  task_role_arn             = aws_iam_role.catalog_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "catalog"
      image     = "${aws_ecr_repository.catalog.repository_url}:${var.catalog_image_tag}"
      essential = true
      portMappings = [{
        containerPort = var.catalog_container_port
        protocol      = "tcp"
      }]
      # Config confirmed against Catalog's own README and repository.go
      # (see docs/architecture.md Decisions and Verification Log):
      # - PROVIDER value "mysql" confirmed via README's own documented
      #   values table (in-memory or mysql).
      # - ENDPOINT confirmed to expect a bare host:port string, inserted
      #   directly inside repository.go's fmt.Sprintf(...tcp(%s)...) DSN
      #   construction. Aurora's cluster endpoint + port, nothing more.
      # - No schema/init step needed: the app runs GORM AutoMigrate on
      #   startup and self-seeds product/tag data from its own bundled
      #   JSON files.
      environment = [
        {
          name  = "RETAIL_CATALOG_PERSISTENCE_PROVIDER"
          value = "mysql"
        },
        {
          name  = "RETAIL_CATALOG_PERSISTENCE_ENDPOINT"
          value = "${aws_rds_cluster.catalog.endpoint}:${aws_rds_cluster.catalog.port}"
        },
        {
          name  = "RETAIL_CATALOG_PERSISTENCE_DB_NAME"
          value = var.aurora_db_name
        }
      ]
      # Username and password come from a Terraform-generated secret
      # (see aurora.tf), via JSON key extraction, never as plain
      # environment values on the task definition itself. Unlike Carts'
      # DynamoDB access or Checkout's original design intent, this secret
      # IS in Terraform state, a deliberate, documented tradeoff (see
      # DECISIONS.md) to guarantee a MySQL-DSN-safe password rather than
      # risk another AWS-generated punctuation character breaking the
      # connection.
      secrets = [
        {
          name      = "RETAIL_CATALOG_PERSISTENCE_USER"
          valueFrom = "${aws_secretsmanager_secret.aurora_master.arn}:username::"
        },
        {
          name      = "RETAIL_CATALOG_PERSISTENCE_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.aurora_master.arn}:password::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "catalog"
        }
      }
      # /catalogue (the README's documented "test access" endpoint) was
      # tried first and confirmed WRONG the hard way: every health check
      # against it returned a clean 404 in CloudWatch Logs, while real
      # traffic from UI (source IP inside the VPC, not localhost) was
      # simultaneously succeeding against /catalog/products with a real
      # 200. The README's documented command was outdated or inaccurate
      # for this deployed version - confirmed against live request logs,
      # not just written docs, which is exactly why this got caught after
      # deploy instead of before: nothing short of a real request would
      # have surfaced this.
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.catalog_container_port}/catalog/products || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-catalog-taskdef"
  }
}

resource "aws_ecs_service" "catalog" {
  name            = "catalog"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.catalog.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.catalog_task.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.catalog.arn
  }

  tags = {
    Name = "${var.project_name}-catalog-service"
  }
}
