#!/usr/bin/env bash
# One-time (or per-version-bump) script: mirrors the two public.ecr.aws
# images this project depends on into this project's own private ECR
# repositories (see infra/ecr.tf).
#
# Why this exists: public.ecr.aws is not reliably reachable from a private
# subnet with no NAT Gateway, even with a dedicated ecr-public.api VPC
# endpoint - that endpoint covers API/metadata calls, not the actual image
# pull path. Mirroring sidesteps the problem and is also a reasonable
# supply-chain hardening step on its own.
#
# Prerequisites:
#   - Docker running locally
#   - AWS CLI configured with credentials that have ECR push permissions
#   - The ECR repositories in infra/ecr.tf must already exist
#     (run `tofu apply` first - the repos are created even if the ECS
#     services that reference them fail to pull until this script runs)
#
# Usage:
#   ./scripts/mirror-images.sh

set -euo pipefail

AWS_REGION="us-east-1"
PROJECT_NAME="retail-multitier"
IMAGE_TAG="1.2.4"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Authenticating Docker with ECR (${ECR_REGISTRY})..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

mirror_image() {
  local source_image="$1"
  local target_repo="$2"

  echo ""
  echo "=== Mirroring ${source_image} -> ${target_repo}:${IMAGE_TAG} ==="

  docker pull "${source_image}"
  docker tag "${source_image}" "${ECR_REGISTRY}/${target_repo}:${IMAGE_TAG}"
  docker push "${ECR_REGISTRY}/${target_repo}:${IMAGE_TAG}"
}

mirror_image "public.ecr.aws/aws-containers/retail-store-sample-ui:${IMAGE_TAG}" \
  "${PROJECT_NAME}/retail-store-sample-ui"

mirror_image "public.ecr.aws/aws-containers/retail-store-sample-cart:${IMAGE_TAG}" \
  "${PROJECT_NAME}/retail-store-sample-cart"

echo ""
echo "Done. Both images are now in your private ECR repos."
echo "If the ECS services already exist and are stuck retrying failed pulls,"
echo "force a fresh deployment so they pick up the now-available images"
echo "immediately instead of waiting for the next automatic retry:"
echo ""
echo "  aws ecs update-service --cluster ${PROJECT_NAME}-cluster --service ui --force-new-deployment --region ${AWS_REGION}"
echo "  aws ecs update-service --cluster ${PROJECT_NAME}-cluster --service carts --force-new-deployment --region ${AWS_REGION}"
