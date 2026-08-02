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

# ---- Catalog: dedicated task execution role, NOT the shared one ----
# ECS uses the task EXECUTION role (not the task role) to fetch secrets
# referenced in a container's "secrets" block at launch time. The shared
# task_execution role above is used by all three services; giving Catalog
# its own execution role keeps read access to Aurora's credentials scoped
# to Catalog only, rather than technically also granting UI and Carts a
# permission they have no reason to use. Same reasoning as every other
# least-privilege decision in this project - unused access is still risk.
resource "aws_iam_role" "catalog_task_execution" {
  name = "${var.project_name}-catalog-task-execution-role"

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

resource "aws_iam_role_policy_attachment" "catalog_task_execution_managed" {
  role       = aws_iam_role.catalog_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "catalog_task_execution_secrets" {
  name = "${var.project_name}-catalog-secrets-policy"
  role = aws_iam_role.catalog_task_execution.id

  # Scoped to the one Aurora-managed secret only. If this fails at deploy
  # time with an access-denied error mentioning KMS rather than Secrets
  # Manager, the next step is an explicit kms:Decrypt grant on the
  # secret's KMS key - not expected to be necessary with the default
  # AWS-managed secretsmanager key, but not yet confirmed against a real
  # deploy either.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_rds_cluster.catalog.master_user_secret[0].secret_arn
    }]
  })
}

# ---- Catalog task role (no additional AWS API calls at runtime -
# Catalog only talks to Aurora over plain MySQL, confirmed via
# repository.go) ----
resource "aws_iam_role" "catalog_task" {
  name = "${var.project_name}-catalog-task-role"

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
