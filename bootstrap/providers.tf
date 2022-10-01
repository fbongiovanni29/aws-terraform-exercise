terraform {
  required_version = ">= 1.3"
  backend "s3" {
    bucket = "terraform-backend-fbongiovanni"
    key    = "aws-terraform-exercise-bootstrap"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
