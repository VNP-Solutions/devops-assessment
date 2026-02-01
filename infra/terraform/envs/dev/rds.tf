resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:?"  # Exclude /, @, ", and space
}
resource "aws_security_group" "rds" {
name = "${local.name_prefix}-rds-sg"
description = "Allow Postgres from EKS nodes"
vpc_id = module.vpc.vpc_id
tags = local.tags
}
resource "aws_security_group_rule" "rds_ingress_from_nodes" {
type = "ingress"
from_port = 5432
to_port = 5432
protocol = "tcp"
security_group_id = aws_security_group.rds.id
source_security_group_id = module.eks.node_security_group_id
}
resource "aws_db_subnet_group" "db" {
name = "${local.name_prefix}-db-subnets"
subnet_ids = module.vpc.database_subnets
tags = local.tags
}
resource "aws_db_instance" "postgres" {
identifier = "${local.name_prefix}-postgres"
engine = "postgres"
engine_version = "15"
instance_class = var.db_instance_class
allocated_storage = var.db_allocated_storage
storage_encrypted = true
db_name = "toy_production"
username = "toyapp"
password = random_password.db.result
db_subnet_group_name = aws_db_subnet_group.db.name
vpc_security_group_ids = [aws_security_group.rds.id]
publicly_accessible = false
skip_final_snapshot = true
tags = local.tags
}
resource "aws_secretsmanager_secret" "db" {
name = "${local.name_prefix}/database"
tags = local.tags
}
resource "aws_secretsmanager_secret_version" "db" {
secret_id = aws_secretsmanager_secret.db.id
secret_string = jsonencode({
username = aws_db_instance.postgres.username
password = random_password.db.result
host = aws_db_instance.postgres.address
port = aws_db_instance.postgres.port
dbname = aws_db_instance.postgres.db_name
database_url = "postgres://${aws_db_instance.postgres.username}:${random_password.db.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
})
}