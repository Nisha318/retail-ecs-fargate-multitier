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
  description = "SOURCE image for the UI service - public.ecr.aws, confirmed pullable via docker pull. This is used as the reference for scripts/mirror-images.sh, NOT as the image the ECS task definition actually pulls from. See ecr.tf and image_tag: the task definition pulls from the private ECR mirror instead, since public.ecr.aws is not reliably reachable from a private subnet with no NAT Gateway."
  type        = string
  default     = "public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.4"
}

variable "carts_image" {
  description = "SOURCE image for the Carts service - public.ecr.aws, confirmed pullable via docker pull. Repository name confirmed via gallery.ecr.aws/aws-containers/retail-store-sample-cart (singular - the older ECS Immersion Day workshop used the now-outdated plural 'retail-store-sample-carts'). This is used as the reference for scripts/mirror-images.sh, NOT as the image the ECS task definition actually pulls from. See ecr.tf and image_tag."
  type        = string
  default     = "public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.4"
}

variable "image_tag" {
  description = "Tag used both for the source pull (from public.ecr.aws, must match the tag in ui_image/carts_image) and for the mirrored image pushed into this project's private ECR repos. Kept as a single shared variable so the two stay in sync deliberately rather than by convention."
  type        = string
  default     = "1.2.4"
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

# --- Phase 2: Catalog + Aurora MySQL ---

variable "catalog_image" {
  description = "SOURCE image for the Catalog service - public.ecr.aws. Repository name and tag NOT YET CONFIRMED via docker pull, unlike ui_image/carts_image. Confirm before first apply, same discipline that caught the plural/singular 'cart' naming issue in Phase 1. Used as the reference for scripts/mirror-images.sh, not what the task definition actually pulls from."
  type        = string
  default     = "public.ecr.aws/aws-containers/retail-store-sample-catalog:1.2.4"
}

variable "catalog_image_tag" {
  description = "Tag for the Catalog source pull and its private ECR mirror. Kept separate from image_tag (UI/Carts) since Catalog may release on a different cadence - confirm this tag actually exists via docker pull before first apply."
  type        = string
  default     = "1.2.4"
}

variable "catalog_container_port" {
  type    = number
  default = 8080
}

variable "aurora_db_name" {
  description = "Matches Catalog's own default (RETAIL_CATALOG_PERSISTENCE_DB_NAME), confirmed via the service's README and source. Not a value we chose independently."
  type        = string
  default     = "catalogdb"
}

variable "aurora_master_username" {
  description = "Matches Catalog's own default (RETAIL_CATALOG_PERSISTENCE_USER), confirmed via the service's README and source."
  type        = string
  default     = "catalog_user"
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 ACUs. 0 enables auto-pause when idle (supported on the engine version pinned in aurora.tf), which is the right default for a project that gets torn down between sessions rather than left running."
  type        = number
  default     = 0
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs. Kept low deliberately - this is a personal project's dev/test catalog database, not a production workload sized for real traffic."
  type        = number
  default     = 2
}
