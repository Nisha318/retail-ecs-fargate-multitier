data "aws_caller_identity" "current" {}

# ---- Shared task execution role (ECS agent: pull image, write logs) ----
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---- UI task role (no AWS API calls needed in Phase 1) ----
resource "aws_iam_role" "ui_task" {
  name = "${var.project_name}-ui-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# ---- Carts task role (scoped to the specific DynamoDB table only) ----
resource "aws_iam_role" "carts_task" {
  name = "${var.project_name}-carts-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "carts_dynamodb" {
  name = "${var.project_name}-carts-dynamodb-policy"
  role = aws_iam_role.carts_task.id

  # Action list mirrors what the carts service actually needs against a
  # single-table design: item-level CRUD plus query (for the GSI) and
  # DescribeTable for startup validation. Confirm against actual container
  # behavior during first deploy per docs/architecture.md open items.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:DescribeTable"
      ]
      Resource = [
        aws_dynamodb_table.carts.arn,
        "${aws_dynamodb_table.carts.arn}/index/*"
      ]
    }]
  })
}
