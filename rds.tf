data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_secretsmanager_secret" "db_password" {
  arn = var.database_password_secret_arn
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}

resource "aws_iam_role_policy" "db_secrets" {
  name = "${var.unique_name}-read-db-pass-secret"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
        ]
        Resource = [
          data.aws_secretsmanager_secret_version.db_password.arn,
        ]
      },
    ]
  })
}
/*
resource "aws_db_subnet_group" "rds" {
  name       = "${var.unique_name}-rds"
  subnet_ids = var.database_subnet_ids
}

resource "aws_security_group" "rds" {
  name   = "${var.unique_name}-rds"
  vpc_id = var.vpc_id
  tags   = local.tags

  ingress {
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster" "backend_store" {
  cluster_identifier_prefix = var.unique_name
  tags                      = local.tags
  engine                    = "aurora-postgresql"
  engine_version            = "aurora-postgresql10"
  engine_mode               = "serverless"
  port                      = local.db_port
  db_subnet_group_name      = aws_db_subnet_group.rds.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  # availability_zones        = [data.aws_availability_zones.available.names] # ref https://github.com/terraform-aws-modules/terraform-aws-rds-aurora/pull/10
  master_username           = "ecs_task"
  database_name             = "mlflow"
  skip_final_snapshot       = var.database_skip_final_snapshot
  final_snapshot_identifier = var.unique_name
  master_password           = data.aws_secretsmanager_secret_version.db_password.secret_string
  backup_retention_period   = 14

  scaling_configuration {
    max_capacity             = var.database_max_capacity
    min_capacity             = var.database_min_capacity
    auto_pause               = var.database_auto_pause
    seconds_until_auto_pause = var.database_seconds_until_auto_pause
    timeout_action           = "ForceApplyCapacityChange"
  }
}
*/
################################################################################
# RDS Aurora Module
################################################################################
module "aurora_postgresql" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-rds-aurora.git?ref=v6.1.3"

  name                            = lower("${var.unique_name}-postgresql")
  engine                          = "aurora-postgresql"
  engine_mode                     = "serverless"
  database_name                   = "mlflow_db"
  engine_version                  = null
  storage_encrypted               = true
  vpc_id                          = var.vpc_id
  subnets                         = var.database_subnet_ids
  create_security_group           = true
  allowed_security_groups         = concat([aws_security_group.ecs_service.id],var.additional_sg)
  monitoring_interval             = 60
  apply_immediately               = true
  skip_final_snapshot             = true
  db_parameter_group_name         = aws_db_parameter_group.aurora_postgresql.id
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_postgresql.id

  scaling_configuration           = {
    auto_pause     = false
    min_capacity   = 2
    max_capacity   = 16
    timeout_action = "ForceApplyCapacityChange"
  }

  master_username                 = "ecs_task"
  master_password                 = data.aws_secretsmanager_secret_version.db_password.secret_string
  create_random_password          = false
  tags                            = local.tags

}

resource "aws_db_parameter_group" "aurora_postgresql" {
  name        = lower("${var.unique_name}-aurora-db-postgres-parameter-group")
  family      = "aurora-postgresql10"
  description = lower("${var.unique_name}-aurora-db-postgres-parameter-group")
  tags        = local.tags
}

resource "aws_rds_cluster_parameter_group" "aurora_postgresql" {
  name        = lower("${var.unique_name}-aurora-postgres-cluster-parameter-group")
  family      = "aurora-postgresql10"
  description = lower("${var.unique_name}-aurora-postgres-cluster-parameter-group")
  tags        = local.tags
}

