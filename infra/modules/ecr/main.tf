locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)
  name     = "${local.name_prefix}-${each.key}"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "retain_recent" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain last 20 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "repositories" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

