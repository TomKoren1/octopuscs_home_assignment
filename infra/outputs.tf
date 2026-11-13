output "app_url" {
  description = "Where the site is served."
  value       = "http://${aws_instance.app.public_ip}"
}

output "region" {
  value = var.region
}

output "instance_id" {
  value = aws_instance.app.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "deploy_role_arn" {
  description = "Role that GitHub Actions assumes."
  value       = aws_iam_role.deploy.arn
}

output "ssm_document_name" {
  value = aws_ssm_document.deploy.name
}

output "shell_on_the_server" {
  description = "Open a shell without SSH (needs the Session Manager plugin)."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.app.id}"
}

output "github_repo" {
  value = var.github_repo
}
