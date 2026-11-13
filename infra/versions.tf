terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State is kept in a local file (terraform.tfstate, git-ignored).
  # That is deliberate for this exercise: one person, apply-then-destroy,
  # and nothing left behind in the account. A team would use an S3 backend
  # with locking instead:
  #
  #   backend "s3" {
  #     bucket       = "my-terraform-state"
  #     key          = "octopus-apples/terraform.tfstate"
  #     region       = "eu-central-1"
  #     use_lockfile = true
  #   }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags: easy to find, easy to audit.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
