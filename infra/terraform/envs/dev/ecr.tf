resource "aws_ecr_repository" "user" {
name = "${local.name_prefix}-user-service"
image_tag_mutability = "MUTABLE"
force_delete = true
tags = local.tags
}
resource "aws_ecr_repository" "product" {
name = "${local.name_prefix}-product-service"
image_tag_mutability = "MUTABLE"
force_delete = true
tags = local.tags
}
resource "aws_ecr_repository" "order" {
name = "${local.name_prefix}-order-service"
image_tag_mutability = "MUTABLE"
force_delete = true
tags = local.tags
}
resource "aws_ecr_lifecycle_policy" "default" {
for_each = {
user = aws_ecr_repository.user.name
product = aws_ecr_repository.product.name
order = aws_ecr_repository.order.name
}
repository = each.value
policy = jsonencode({
rules = [{
rulePriority = 1
description = "Keep last 20 images"
selection = {
tagStatus = "any"
countType = "imageCountMoreThan"
countNumber = 20
}
action = { type = "expire" }
}]
})
}