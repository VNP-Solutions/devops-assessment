data "aws_availability_zones" "available" {}
module "vpc" {
source = "terraform-aws-modules/vpc/aws"
version = "~> 5.0"
name = local.name_prefix
cidr = var.vpc_cidr
azs = slice(data.aws_availability_zones.available.names, 0, 2)
public_subnets = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)]
private_subnets = [cidrsubnet(var.vpc_cidr, 4, 2), cidrsubnet(var.vpc_cidr, 4, 3)]
database_subnets = [cidrsubnet(var.vpc_cidr, 4, 4), cidrsubnet(var.vpc_cidr, 4, 5)]
enable_nat_gateway = true
single_nat_gateway = true
enable_dns_hostnames = true
enable_dns_support = true
public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
tags = local.tags
}
module "eks" {
source = "terraform-aws-modules/eks/aws"
version = "~> 20.0"
cluster_name = "${local.name_prefix}-eks"
cluster_version = var.cluster_version
vpc_id = module.vpc.vpc_id
subnet_ids = module.vpc.private_subnets
enable_irsa = true
cluster_endpoint_public_access = true
eks_managed_node_groups = {
default = {
name = "${local.name_prefix}-ng"
instance_types = var.node_instance_types
min_size = var.node_min_size
max_size = var.node_max_size
desired_size = var.node_desired_size
subnet_ids = module.vpc.private_subnets
disk_size = 20
ami_type = "AL2_x86_64"
tags = local.tags
}
}
tags = local.tags
}