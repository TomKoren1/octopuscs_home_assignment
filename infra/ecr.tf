# Private registry for the app image.
resource "aws_ecr_repository" "app" {
  name = var.project

  # A tag (= git commit SHA) can never be overwritten: what was tested is
  # exactly what runs.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Let `terraform destroy` delete the repository even if it holds images.
  force_delete = true
}

# Keep only the newest 5 images (stays far below the 500 MB free tier).
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
