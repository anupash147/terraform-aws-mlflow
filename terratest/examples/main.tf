provider "aws" {
  region = "us-east-1"
  shared_credentials_file       = "~/.aws/credentials"
  profile                       = "saml"
  
}

resource "random_id" "id" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "mlflow-terratest"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = "ran${random_id.id.hex}dom"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">2.44.0"

  name               = "mlflow-${random_id.id.hex}"
  cidr               = "10.61.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets    = ["10.61.1.0/24", "10.61.2.0/24", "10.61.3.0/24"]
  public_subnets     = ["10.61.101.0/24", "10.61.102.0/24", "10.61.103.0/24"]
  database_subnets   = ["10.61.201.0/24", "10.61.202.0/24", "10.61.203.0/24"]
  enable_nat_gateway = true

  tags = {
    "built-using" = "terratest"
    "env"         = "test"
  }
}


module "bastion" {
  source = "git::ssh://git@github.platforms.engineering/science-at-scale/infrastructure-management//terraform//aws//modules//network//jumpbox?ref=b8b6c3c"

  vpc_id    = module.vpc.vpc_id
  vpc_name  = module.vpc.name
  subnet_id = module.vpc.public_subnets[0]
  key_name  = "elyeq-mr-np"

  cost_tags = { Name = "mlflow-terratest-bastion" }
}

variable "is_private" {
  type = bool
  default = "false"
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
  vpc_id                            = module.vpc.vpc_id
  database_subnet_ids               = module.vpc.private_subnets
  service_subnet_ids                = module.vpc.private_subnets
  load_balancer_subnet_ids          = var.is_private ? module.vpc.private_subnets : module.vpc.public_subnets
  load_balancer_ingress_cidr_blocks = var.is_private ? [module.vpc.vpc_cidr_block] : ["0.0.0.0/0"]
  load_balancer_is_internal         = var.is_private
  artifact_bucket_id                = var.artifact_bucket_id
  database_password_secret_arn      = aws_secretsmanager_secret_version.db_password.secret_id
  database_skip_final_snapshot      = true
  additional_sg                     = [ module.bastion.sg_id ]
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
