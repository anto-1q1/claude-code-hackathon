terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Production backend — uncomment when AWS account is available
  # backend "s3" {
  #   bucket         = "contoso-terraform-state"
  #   key            = "cloud-migration/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   dynamodb_table = "contoso-terraform-locks"
  #   kms_key_id     = "alias/terraform-state"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "contoso-cloud-migration"
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "TimisA"
    }
  }
}

# ── Modules ──────────────────────────────────────────────────────────────────

module "networking" {
  source      = "./modules/networking"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "storage" {
  source      = "./modules/storage"
  environment = var.environment
}

module "secrets" {
  source      = "./modules/secrets"
  environment = var.environment
  db_username = var.db_username
}

module "cache" {
  source             = "./modules/cache"
  environment        = var.environment
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [module.networking.sg_cache_id]
}

module "database" {
  source                = "./modules/database"
  environment           = var.environment
  subnet_ids            = module.networking.private_subnet_ids
  security_group_ids    = [module.networking.sg_db_id]
  db_username           = var.db_username
  db_secret_arn         = module.secrets.db_secret_arn
}

module "webapp" {
  source               = "./modules/webapp"
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  private_subnet_ids   = module.networking.private_subnet_ids
  sg_alb_id            = module.networking.sg_alb_id
  sg_webapp_id         = module.networking.sg_webapp_id
  db_proxy_endpoint    = module.database.proxy_endpoint
  db_secret_arn        = module.secrets.db_secret_arn
  redis_endpoint       = module.cache.redis_endpoint
  reports_bucket_name  = module.storage.webapp_bucket_name
  reports_bucket_arn   = module.storage.webapp_bucket_arn
  acm_certificate_arn  = var.acm_certificate_arn
}

module "batch" {
  source               = "./modules/batch"
  environment          = var.environment
  private_subnet_ids   = module.networking.private_subnet_ids
  sg_batch_id          = module.networking.sg_batch_id
  db_proxy_endpoint    = module.database.proxy_endpoint
  db_secret_arn        = module.secrets.db_secret_arn
  output_bucket_name   = module.storage.batch_bucket_name
  output_bucket_arn    = module.storage.batch_bucket_arn
  webapp_warmup_arn    = module.webapp.warmup_task_arn
  webapp_cluster_arn   = module.webapp.cluster_arn
  webapp_subnet_ids    = module.networking.private_subnet_ids
  webapp_sg_id         = module.networking.sg_webapp_id
}
