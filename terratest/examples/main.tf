provider "aws" {
  region = "us-east-1"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "saml"
}

variable "vpc_id" {
  type = string
  default = "vpc-05df174b01d5d01dd"
}

resource "random_id" "id" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "mlflow-terratest"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  #secret_string = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.rds.secret_string))["password"]
  secret_string = "UfZgUZdua5"
}
/*
data "aws_secretsmanager_secret" "by-arn" {
  arn = "arn:aws:secretsmanager:us-east-1:437491031743:secret:rds-db-credentials/cluster-PRIDKZBGUF6XLUPED5DNH77ZRU/mre_v1-jXZH2q"
}

data "aws_secretsmanager_secret_version" "rds" {
  secret_id = data.aws_secretsmanager_secret.by-arn.id
}
*/
/*
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">2.44.0"

  name               = "mlflow-${random_id.id.hex}"
  cidr               = "10.0.0.0/16"
  azs                = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets   = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  enable_nat_gateway = true

  tags = {
    "built-using" = "terratest"
    "env"         = "test"
  }
}
*/

data "aws_subnet_ids" "Public" {
  filter {
    name   = "tag:Name"
    values = ["*-public-*"] # insert values here
  }
  vpc_id = var.vpc_id
}


data "aws_subnet_ids" "Private" {
  filter {
    name   = "tag:Name"
    values = ["*-private-*"] # insert values here
  }
  vpc_id = var.vpc_id
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

variable "is_private" {
  type = bool
  default = false
}

variable "artifact_bucket_id" {
  default = null
}

module "mlflow" {
  source = "../../"

  unique_name = "mlflow-terratest-${random_id.id.hex}"
  tags = {
    "owner" = "terratest"
  }
  vpc_id                            = var.vpc_id
  # database_subnet_ids               = module.vpc.database_subnets
  service_subnet_ids                = data.aws_subnet_ids.Private.ids
  load_balancer_subnet_ids          = var.is_private ? data.aws_subnet_ids.Private.ids : data.aws_subnet_ids.Public.ids
  load_balancer_ingress_cidr_blocks = var.is_private ? [data.aws_vpc.vpc.cidr_block] : ["0.0.0.0/0"]
  load_balancer_is_internal         = var.is_private
  artifact_bucket_id                = var.artifact_bucket_id
  database_password_secret_arn      = aws_secretsmanager_secret_version.db_password.secret_id
  # database_skip_final_snapshot      = true
  use_rds                           = true
  database                      = "example-serverless-postgresql"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = module.mlflow.load_balancer_arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.mlflow.load_balancer_target_group_id
    type             = "forward"
  }
}

# Outputs for Terratest to use
output "load_balancer_dns_name" {
  value = module.mlflow.load_balancer_dns_name
}

output "artifact_bucket_id" {
  value = module.mlflow.artifact_bucket_id
}
