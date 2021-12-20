data "aws_secretsmanager_secret" "db_password" {
  arn = var.database_password_secret_arn
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}

/*
data "aws_db_instance" "database" {
  db_instance_identifier = var.database
}*/

data "aws_rds_cluster" "database" {
  cluster_identifier = var.database
}

# create a new database for use by mlflow
# local exec


# add ecs security group to the rds security group
resource "aws_security_group_rule" "default_ingress" {
  description = "Access from ECS group"

  type                     = "ingress"
  from_port                = data.aws_rds_cluster.database.port
  to_port                  = data.aws_rds_cluster.database.port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id
  security_group_id        = join(",", data.aws_rds_cluster.database.vpc_security_group_ids)
}



