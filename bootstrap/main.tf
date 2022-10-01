# Bucket for remote terraform backend
#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "backend" {
  bucket = "terraform-backend-fbongiovanni"
}

# Private ACL for bucket
resource "aws_s3_bucket_acl" "backend" {
  bucket = aws_s3_bucket.backend.id
  acl    = "private"
}

# Always version terraform backends
resource "aws_s3_bucket_versioning" "backend" {
  bucket = aws_s3_bucket.backend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Key to encrypt backend bucket
resource "aws_kms_key" "backend" {
  description             = "This key is used to encrypt the terraform backend bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

# Configure encryption on bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "backend" {
  bucket = aws_s3_bucket.backend.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backend.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Block public access from bucket
resource "aws_s3_bucket_public_access_block" "backend" {
  bucket                  = aws_s3_bucket.backend.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
