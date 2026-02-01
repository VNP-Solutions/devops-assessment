locals {
name_prefix = "${var.project}-${var.env}"
tags = {
Project = var.project
Environment = var.env
ManagedBy = "terraform"
}
}