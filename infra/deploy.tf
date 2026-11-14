# GitHub Actions deploys with OIDC (no AWS keys). Its role may only push to our
# ECR repo and run this one document, whose only input is a commit SHA.
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
        allowedPattern = "^[0-9a-f]{40}$"
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
          "git fetch --quiet origin",
          "git checkout --quiet --force {{ ImageTag }}",
          "APP_IMAGE=${aws_ecr_repository.app.repository_url}:{{ ImageTag }} ./provision.sh",
          "docker image prune -af >/dev/null",
        ]
      }
    }]
  })
}

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
