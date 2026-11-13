# ---- How GitHub Actions deploys ----------------------------------------------
#
#   GitHub job --(OIDC token)--> IAM role --> push image to ECR
#                                        \--> start ONE SSM document on ONE instance
#
# No AWS access keys exist anywhere. The role can only be assumed by the
# main branch of our repository, and it cannot run arbitrary commands on
# the server: only the fixed script below, with a commit SHA as its input.

# The script that runs on the server for each deploy.
resource "aws_ssm_document" "deploy" {
  name            = "${var.project}-deploy"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy one commit of ${var.project}"
    parameters = {
      ImageTag = {
        type           = "String"
        description    = "Git commit SHA = image tag to deploy"
        allowedPattern = "^[0-9a-f]{40}$" # nothing but a full SHA is accepted
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deploy"
      inputs = {
        timeoutSeconds = "600"
        runCommand = [
          "#!/bin/bash",
          "set -eu",
          "export HOME=/root",
          "cd /opt/octopus-apples",
          # Bring compose files and scripts to the same commit as the image
          "git fetch --quiet origin",
          "git checkout --quiet --force {{ ImageTag }}",
          # Pull that image from ECR, restart, wait for health, smoke-test
          "APP_IMAGE=${aws_ecr_repository.app.repository_url}:{{ ImageTag }} ./provision.sh",
          # Free disk space: remove images that are no longer used
          "docker image prune -af >/dev/null",
        ]
      }
    }]
  })
}

# GitHub's OIDC identity provider: created here, or looked up if the
# account already has one.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

resource "aws_iam_role" "deploy" {
  name = "${var.project}-github-deploy"

  # WHO may assume the role: GitHub Actions jobs of our repo's main branch.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${var.github_oidc_subject_prefix}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# WHAT the role may do: push to one repository, run one document on one instance.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this action does not support resource-level permissions
      },
      {
        Sid    = "PushToOurRepositoryOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "RunTheDeployDocumentOnOurInstanceOnly"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          aws_ssm_document.deploy.arn,
          aws_instance.app.arn,
        ]
      },
      {
        Sid      = "ReadCommandResult"
        Effect   = "Allow"
        Action   = "ssm:GetCommandInvocation"
        Resource = "*" # this action does not support resource-level permissions
      },
    ]
  })
}
