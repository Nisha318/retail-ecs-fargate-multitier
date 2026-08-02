locals {
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoints)
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-${each.value}"
  }
}

# S3 gateway endpoint: ECR stores image layers in S3, so this is required
# alongside the ecr.api / ecr.dkr interface endpoints for image pulls to
# succeed from a subnet with no internet route. Confirm during first deploy
# per docs/architecture.md open items.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-vpce-s3"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-vpce-dynamodb"
  }
}

# Public ECR (public.ecr.aws) is NOT covered by the ecr.api / ecr.dkr
# interface endpoints above - those only provide private connectivity to
# PRIVATE ECR repositories in this account. Amazon ECR Public Gallery
# images (which this project pulls: retail-store-sample-ui,
# retail-store-sample-cart) require this separate, dedicated endpoint.
# Confirmed the hard way: task launch failed with CannotPullContainerError
# / i/o timeout resolving public.ecr.aws before this endpoint was added.
#
# Service name requires the ".api" suffix - "com.amazonaws.us-east-1.ecr-
# public" alone does not exist and fails with InvalidServiceName. The
# correct name was confirmed directly against AWS (not just documentation)
# via: aws ec2 describe-vpc-endpoint-services --region us-east-1
#   --filters "Name=service-name,Values=*ecr*"
#
# AWS restricts this endpoint to us-east-1 only (per AWS's own ECR VPC
# endpoint documentation: "VPC endpoints support Amazon ECR Public
# repositories through the AWS API SDK endpoint in US East (N. Virginia)").
# The precondition below fails cleanly at plan time rather than as a
# confusing runtime image-pull timeout if this project is ever deployed
# to a different region.
resource "aws_vpc_endpoint" "ecr_public" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ecr-public.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  lifecycle {
    precondition {
      condition     = var.aws_region == "us-east-1"
      error_message = "The ecr-public.api VPC endpoint is only available in us-east-1. Public ECR image pulls from a private subnet will fail in any other region without a NAT Gateway or other internet route."
    }
  }

  tags = {
    Name = "${var.project_name}-vpce-ecr-public"
  }
}
