#!/usr/bin/env bash
# Create the AWS infra, connect the pipeline to it, wait for the site. Needs terraform, aws, gh.
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

[ -f terraform.tfvars ] || echo "Note: no terraform.tfvars - using defaults (see terraform.tfvars.example)"

log "Terraform: plan and apply (you will be asked to confirm)"
terraform init -input=false >/dev/null
terraform apply "$@"

# Not secrets. While they exist, pushes to main are deployed.
log "Publishing the outputs to GitHub repository variables"
repo="$(terraform output -raw github_repo)"
gh variable set AWS_ROLE_ARN       --repo "$repo" --body "$(terraform output -raw deploy_role_arn)"
gh variable set AWS_REGION         --repo "$repo" --body "$(terraform output -raw region)"
gh variable set ECR_REPOSITORY_URL --repo "$repo" --body "$(terraform output -raw ecr_repository_url)"
gh variable set EC2_INSTANCE_ID    --repo "$repo" --body "$(terraform output -raw instance_id)"
gh variable set SSM_DOCUMENT_NAME  --repo "$repo" --body "$(terraform output -raw ssm_document_name)"
gh variable set APP_URL            --repo "$repo" --body "$(terraform output -raw app_url)"

url="$(terraform output -raw app_url)"
log "Waiting for the server's first boot (installs Docker, starts the stack) - up to 10 minutes"
for i in $(seq 60); do
  if curl -fsS -m 5 "$url/health" >/dev/null 2>&1; then
    printf '\n\033[1;32mOK - the site is live: %s\033[0m\n' "$url"
    exit 0
  fi
  printf '.'
  sleep 10
done
printf '\n\033[1;31mThe site did not answer in time. Check /var/log/cloud-init-output.log on the server:\033[0m\n'
terraform output -raw shell_on_the_server; echo
exit 1
