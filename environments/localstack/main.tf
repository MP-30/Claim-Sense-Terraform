terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  gateway = "http://127.0.0.1:4566"
}

provider "aws" {
  region                      = "ap-south-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    cloudwatchlogs = local.gateway
    ec2            = local.gateway
    ecr            = local.gateway
    ecs            = local.gateway
    iam            = local.gateway
    rds            = local.gateway
    s3             = local.gateway
    sts            = local.gateway
  }
}

module "foundation" {
  source   = "../../modules/foundation"
  app_name = "claimsense"
}

output "documents_bucket" {
  value = module.foundation.documents_bucket
}

output "ecr_repository_url" {
  value = module.foundation.ecr_repository_url
}

output "log_group" {
  value = module.foundation.log_group
}

output "cluster_name" {
  value = module.foundation.cluster_name
}
