#!/usr/bin/env bash
# Runs the exact same three security scans as .github/workflows/pipeline.yml,
# locally, before you ever push. Same Docker images, same skip lists, same
# tools CI uses, so a clean local run means a clean CI run, not just an
# approximation of one.
#
# Why this exists: every Checkov finding tonight went through a push, wait
# for CI, read the failure, fix, push again loop. Running these locally
# catches the same findings in seconds instead of a full CI round trip.
#
# IMPORTANT: the Checkov skip_check list below must be kept in sync with
# .github/workflows/pipeline.yml manually. If you add a new accepted
# finding to the pipeline, add it here too, or this script will report a
# false failure that CI won't actually flag.
#
# Prerequisites:
#   - Docker running locally
#   - AWS CLI configured, only needed for the Trivy section, which pulls
#     from your private ECR repos (same as scripts/mirror-images.sh)
#
# Usage:
#   ./scripts/local-scan.sh

set -uo pipefail

AWS_REGION="us-east-1"
PROJECT_NAME="retail-multitier"
CHECKOV_SKIP="CKV_AWS_382,CKV_AWS_119,CKV_AWS_150,CKV_AWS_260,CKV_AWS_18,CKV2_AWS_62,CKV_AWS_144,CKV_AWS_145,CKV2_AWS_76,CKV_AWS_136,CKV_AWS_327,CKV_AWS_118,CKV2_AWS_8,CKV_AWS_326,CKV_AWS_162,CKV_AWS_325,CKV_AWS_139,CKV_AWS_354,CKV_AWS_149,CKV_AWS_191,CKV2_AWS_57"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

echo "=== Checkov (infra IaC scan) ==="
# MSYS_NO_PATHCONV=1 disables Git Bash's automatic conversion of
# Unix-style paths into Windows paths for this command. Without it, the
# container-side path in -v mounts (anything after the colon) gets
# silently rewritten into something like C:/Program Files/Git/infra,
# which breaks the mount. This affects every docker run with a -v flag
# in this script, not just this one.
MSYS_NO_PATHCONV=1 docker run --rm -v "${REPO_ROOT}/infra:/infra" ghcr.io/bridgecrewio/checkov:3.3.8 \
  -d /infra --quiet --skip-check "${CHECKOV_SKIP}"
if [ $? -ne 0 ]; then
  echo "Checkov found unaccepted findings."
  FAILED=1
fi

echo ""
echo "=== Gitleaks (secret scan) ==="
MSYS_NO_PATHCONV=1 docker run --rm -v "${REPO_ROOT}:/repo" zricethezav/gitleaks:latest \
  detect --source /repo -v
if [ $? -ne 0 ]; then
  echo "Gitleaks found potential secrets."
  FAILED=1
fi

echo ""
echo "=== Trivy (container image scans) ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

if [ -z "${ACCOUNT_ID}" ]; then
  echo "Skipping Trivy: AWS CLI not configured or not authenticated."
  echo "Run 'aws configure' or set up your credentials, then re-run this script."
else
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

  echo "Authenticating Docker with ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_REGISTRY}" > /dev/null

  # Mounts the host's Docker socket into the Trivy container itself
  # ("Docker outside of Docker"). Without this, Trivy runs fully isolated
  # inside its own container with no access to the host's Docker daemon
  # or its existing ECR login, and falls back to an unauthenticated
  # direct registry pull, which fails with 401 Unauthorized.
  declare -A REPO_TAGS=(
    ["retail-store-sample-ui"]="1.2.4"
    ["retail-store-sample-cart"]="1.2.4"
    ["retail-store-sample-catalog"]="1.2.4"
    ["retail-store-sample-checkout"]="1.2.4"
  )

  for repo in "${!REPO_TAGS[@]}"; do
    tag="${REPO_TAGS[$repo]}"
    echo ""
    echo "--- ${repo}:${tag} ---"
    # --exit-code 0 matches pipeline.yml's Trivy step exactly. Findings
    # in the app's own dependencies (not this project's code) are
    # reported, never failed on, since this project mirrors AWS's public
    # sample app as-is and has no ability to patch its upstream
    # dependencies without forking it, the same line avoided everywhere
    # else in this project (see DECISIONS.md). Without this flag, this
    # script disagreed with what the actual pipeline does, reporting
    # "failed" locally for something that shows green in CI.
    #
    # --timeout 15m: Trivy's own default (5m) isn't enough for larger,
    # dependency-heavy images (confirmed the hard way scanning UI, a
    # Java/Spring Boot image, which has meaningfully more layers to
    # analyze than Catalog's single Go binary). Trivy's own error output
    # names this exact fix directly.
    MSYS_NO_PATHCONV=1 docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      aquasec/trivy:0.36.0 image --severity HIGH,CRITICAL --exit-code 0 --timeout 15m \
      "${ECR_REGISTRY}/${PROJECT_NAME}/${repo}:${tag}"
  done
fi

echo ""
if [ "${FAILED}" -eq 0 ]; then
  echo "All local scans passed. Safe to push."
else
  echo "One or more scans found something. Review above before pushing."
  exit 1
fi
