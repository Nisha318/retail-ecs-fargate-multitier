# Private ECR repositories mirroring the two public images this project
# depends on. Added after confirming (the hard way, during first deploy)
# that public.ecr.aws is not reliably reachable from a private subnet even
# with a dedicated ecr-public.api VPC interface endpoint - that endpoint's
# private DNS covers API/metadata calls, not the actual image pull path,
# which still resolves to public.ecr.aws directly.
#
# Mirroring into private ECR sidesteps the problem entirely: pulls go
# through the ecr.api / ecr.dkr endpoints already proven to work correctly
# in this project (same mechanism the CI pipeline's Trivy scans use).
#
# This is also a legitimate supply-chain hardening step independent of the
# networking problem it solves: task definitions now pull from a registry
# under this account's control, at a specific immutable tag, rather than
# depending on the public gallery's continued availability at apply/deploy
# time.
#
# Images are NOT pushed here by OpenTofu - only the repositories are
# created. See scripts/mirror-images.sh for the one-time push step, which
# must be run after these repositories exist and before (or instead of
# waiting for) ECS's automatic task retry.

resource "aws_ecr_repository" "ui" {
  name                 = "${var.project_name}/retail-store-sample-ui"
  image_tag_mutability = "IMMUTABLE"

  # This is a personal learning project meant to be torn down between
  # sessions, not a production registry. Without this, `tofu destroy`
  # fails outright whenever the mirror script has pushed an image, since
  # ECR refuses to delete a non-empty repository by default. A production
  # version of this infrastructure would leave this false.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr-ui"
  }
}

resource "aws_ecr_repository" "cart" {
  name                 = "${var.project_name}/retail-store-sample-cart"
  image_tag_mutability = "IMMUTABLE"

  # See aws_ecr_repository.ui for why this is intentionally true here.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr-cart"
  }
}

resource "aws_ecr_repository" "catalog" {
  name                 = "${var.project_name}/retail-store-sample-catalog"
  image_tag_mutability = "IMMUTABLE"

  # See aws_ecr_repository.ui for why this is intentionally true here.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr-catalog"
  }
}

resource "aws_ecr_repository" "checkout" {
  name                 = "${var.project_name}/retail-store-sample-checkout"
  image_tag_mutability = "IMMUTABLE"

  # See aws_ecr_repository.ui for why this is intentionally true here.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr-checkout"
  }
}
