terraform {
required_version = ">= 1.5.0"
backend "s3" {}
required_providers {
aws = {
source = "hashicorp/aws"
version = ">= 5.0"
}
kubernetes = {
source = "hashicorp/kubernetes"
version = ">= 2.20"
}
helm = {
source = "hashicorp/helm"
version = ">= 2.10"
}
random = {
source = "hashicorp/random"
version = ">= 3.5"
}
}
}