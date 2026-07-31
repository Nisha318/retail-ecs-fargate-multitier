variable "aws_region" {
  description = "AWS region for this deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for resource naming"
  type        = string
  default     = "retail-multitier"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "ui_image" {
  description = "Container image for the UI service"
  type        = string
  default     = "public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.4"
}

variable "carts_image" {
  description = "Container image for the Carts service. Repository name confirmed via gallery.ecr.aws/aws-containers/retail-store-sample-cart (singular - the older ECS Immersion Day workshop used the now-outdated plural 'retail-store-sample-carts'). Tag not yet confirmed as current/valid - check `docker pull` or `aws ecr-public describe-images` before first apply."
  type        = string
  default     = "public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.4"
}

variable "ui_container_port" {
  type    = number
  default = 8080
}

variable "carts_container_port" {
  type    = number
  default = 8080
}

variable "hosted_zone_domain" {
  description = "Existing Route53 public hosted zone (already reused across projects)"
  type        = string
  default     = "nishacloudprojects.click"
}

variable "site_subdomain" {
  description = "Subdomain this project deploys under, within hosted_zone_domain"
  type        = string
  default     = "retail-multitier"
}
