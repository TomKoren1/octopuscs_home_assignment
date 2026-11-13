#!/usr/bin/env bash
# Delete everything apply.sh created, so the AWS account costs nothing.
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# First disconnect the pipeline: without these variables the deploy job is
# skipped (not failed) on the next push.
log "Removing the GitHub repository variables"
repo="$(terraform output -raw github_repo 2>/dev/null || true)"
if [ -n "$repo" ]; then
  for v in AWS_ROLE_ARN AWS_REGION ECR_REPOSITORY_URL EC2_INSTANCE_ID SSM_DOCUMENT_NAME APP_URL; do
    gh variable delete "$v" --repo "$repo" 2>/dev/null || true
  done
fi

log "Terraform: destroy (you will be asked to confirm)"
terraform destroy "$@"

log "What is left in the Terraform state (should be nothing):"
terraform state list || true
