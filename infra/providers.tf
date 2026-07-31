terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Reuses the existing state bucket / lock table shared across projects
  # (see container-security-progression / Stage 2). This project keeps its
  # own distinct state key so it can never collide with another project's
  # state file in the same bucket.
  backend "s3" {
    bucket         = "anvil-tofu-state"
    key            = "retail-ecs-fargate-multitier/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tofu-state-lock-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
