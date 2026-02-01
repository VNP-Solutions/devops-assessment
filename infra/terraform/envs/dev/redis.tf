resource "aws_security_group" "redis" {
name = "${local.name_prefix}-redis-sg"
description = "Allow Redis from EKS nodes"
vpc_id = module.vpc.vpc_id
tags = local.tags
}
resource "aws_security_group_rule" "redis_ingress_from_nodes" {
type = "ingress"
from_port = 6379
to_port = 6379
protocol = "tcp"
security_group_id = aws_security_group.redis.id
source_security_group_id = module.eks.node_security_group_id
}
resource "aws_elasticache_subnet_group" "redis" {
name = "${local.name_prefix}-redis-subnets"
subnet_ids = module.vpc.database_subnets
tags = local.tags
}
resource "aws_elasticache_replication_group" "redis" {
replication_group_id = "${local.name_prefix}-redis"
description = "Toy Production Redis"
engine = "redis"
node_type = var.redis_node_type
num_cache_clusters = 1
parameter_group_name = "default.redis7"
port = 6379
subnet_group_name = aws_elasticache_subnet_group.redis.name
security_group_ids = [aws_security_group.redis.id]
automatic_failover_enabled = false
transit_encryption_enabled = false
at_rest_encryption_enabled = true
tags = local.tags
}