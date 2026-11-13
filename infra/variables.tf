variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Name used for resources and tags."
  type        = string
  default     = "octopus-apples"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is free-tier eligible in most accounts."
  type        = string
  default     = "t3.micro"
}

variable "github_repo" {
  description = "GitHub repository (owner/name). The server clones it, and only its main branch may deploy."
  type        = string
  default     = "TomKoren1/octopuscs_home_assignment"
}

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Prefix of the "sub" claim in this repository's GitHub OIDC tokens.
    Find it with:
      gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
    Older repositories use the plain form "repo:OWNER/REPO".
  EOT
  type        = string
  default     = "repo:TomKoren1@158804347/octopuscs_home_assignment@1456479308"
}

variable "create_github_oidc_provider" {
  description = "An AWS account can hold only one GitHub OIDC provider. Set to false if the account already has it."
  type        = bool
  default     = true
}
