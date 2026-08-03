# All security groups for this project, consolidated here rather than
# colocated with the resource each one protects, so the full network
# attack surface (every ingress/egress rule in the system) can be reviewed
# in one place. Referenced by resource elsewhere: alb.tf, ecs-cluster.tf,
# ecs-ui.tf, ecs-carts.tf, endpoints.tf.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Public ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere (redirects to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic (ALB must reach targets in any private subnet on any port they listen on)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpce"
  description = "Allows HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic (interface endpoint ENIs do not require egress restriction beyond the VPC boundary)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpce-sg"
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
    description = "All outbound traffic (image pulls, logs, and DynamoDB via VPC endpoints; no NAT Gateway in this design)"
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
    description = "All outbound traffic (image pulls, logs, and DynamoDB via VPC endpoints; no NAT Gateway in this design)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-carts-task-sg"
  }
}

resource "aws_security_group" "catalog_task" {
  name        = "${var.project_name}-catalog-task"
  description = "Catalog Fargate task security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From UI service"
    from_port       = var.catalog_container_port
    to_port         = var.catalog_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ui_task.id]
  }

  egress {
    description = "All outbound traffic (image pulls, logs, Secrets Manager via VPC endpoints, and Aurora on 3306; no NAT Gateway in this design)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-catalog-task-sg"
  }
}

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora"
  description = "Aurora MySQL security group - accepts connections only from the Catalog task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Catalog service only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.catalog_task.id]
  }

  egress {
    description = "No outbound needed - Aurora does not initiate connections"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-aurora-sg"
  }
}

resource "aws_security_group" "checkout_task" {
  name        = "${var.project_name}-checkout-task"
  description = "Checkout Fargate task security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From UI service"
    from_port       = var.checkout_container_port
    to_port         = var.checkout_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ui_task.id]
  }

  egress {
    description = "All outbound traffic (image pulls, logs, and Secrets Manager via VPC endpoints; Redis and Orders API within the VPC; no NAT Gateway in this design)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-checkout-task-sg"
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis"
  description = "ElastiCache Redis security group - accepts connections only from the Checkout task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from Checkout service only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.checkout_task.id]
  }

  egress {
    description = "No outbound needed - Redis does not initiate connections"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}
