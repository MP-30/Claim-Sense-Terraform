# ---------------------------------------------------------------- image registry
resource "aws_ecr_repository" "app" {
  name         = var.app_name
  force_delete = true # lets `terraform destroy` remove the repo even if images exist

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------------------------------------------------------------- logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
}

# Claim documents can contain personal information. Keep the bucket private and
# retain previous versions when an object is replaced or accidentally deleted.
resource "aws_s3_bucket" "documents" {
  bucket_prefix = "claimsense-pdfs-"
  tags          = { Application = var.app_name }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
