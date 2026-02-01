variable "aws_region" { 
    type = string 
    }
variable "project" { 
    type = string 
    }
variable "env" { 
    type = string
    }
variable "cluster_version" {
type = string
default = "1.29"
}
variable "vpc_cidr" {
type = string
default = "10.20.0.0/16"
}
# GitHub OIDC (CI/CD)
variable "github_org" { 
    type = string 
    }
variable "github_repo" { 
    type = string 
    }
variable "github_branch" {
type = string
default = "main"
}
# Sizing (cost control)
variable "node_instance_types" {
type = list(string)
default = ["t3.medium"]
}
variable "node_desired_size" {
type = number
default = 2
}
variable "node_min_size" {
type = number
default = 2
}
variable "node_max_size" {
type = number
default = 3
}
# RDS sizing
variable "db_instance_class" {
type = string
default = "db.t4g.micro"
}
variable "db_allocated_storage" {
type = number
default = 20
}
# Redis sizing
variable "redis_node_type" {
type = string
default = "cache.t4g.micro"
}