terraform {
  required_version = ">= 1.3"
  backend "s3" {
    bucket = "terraform-backend-fbongiovanni"
    key    = "aws-terraform-exercise"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.3"
    }
  }
}

provider "aws" {
  region = local.region
}

provider "tls" {}
