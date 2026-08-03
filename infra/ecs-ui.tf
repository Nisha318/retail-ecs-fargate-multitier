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
      # Pulls from this project's own ECR mirror (ecr.tf), not directly
      # from public.ecr.aws - see ecr.tf for why.
      image     = "${aws_ecr_repository.ui.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{
        containerPort = var.ui_container_port
        protocol      = "tcp"
      }]
      # NOTE: this closes the Phase 1 known gap (see docs/architecture.md)
      # where UI's Catalog dependency was unresolved because Catalog
      # wasn't deployed yet. RETAIL_UI_ENDPOINTS_CATALOG follows the same
      # confirmed Spring Boot relaxed-binding rule as RETAIL_UI_ENDPOINTS_
      # CARTS below - "catalog" is a sibling field in the same
      # EndpointProperties.java class under @ConfigurationProperties
      # ("retail.ui.endpoints"), so this is applying an already-verified
      # rule, not a fresh guess.
      #
      # Confirmed against the actual UI source (EndpointProperties.java):
      # @ConfigurationProperties("retail.ui.endpoints") with a "carts"
      # field binds to env var RETAIL_UI_ENDPOINTS_CARTS via Spring Boot's
      # relaxed binding (dots -> underscores, uppercase). The original
      # RETAIL_CARTS_ENDPOINT name was a plausible-looking guess based on
      # this app family's naming pattern elsewhere, never verified against
      # source - unlike the Carts service's DynamoDB env vars, which were
      # confirmed against real documentation from the start. Wrong name
      # meant EndpointProperties.carts stayed null, which triggered
      # CartClient's fallback to http://localhost:8080 - the UI silently
      # called itself instead of Carts, explaining why nothing ever
      # errored, and why DynamoDB never received a single write despite
      # the app appearing to work perfectly from the browser.
      environment = [
        {
          name  = "RETAIL_UI_ENDPOINTS_CARTS"
          value = "http://carts.${var.project_name}.local:${var.carts_container_port}"
        },
        {
          name  = "RETAIL_UI_ENDPOINTS_CATALOG"
          value = "http://catalog.${var.project_name}.local:${var.catalog_container_port}"
        },
        {
          name  = "RETAIL_UI_ENDPOINTS_CHECKOUT"
          value = "http://checkout.${var.project_name}.local:${var.checkout_container_port}"
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
