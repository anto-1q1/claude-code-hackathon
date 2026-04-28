locals {
  webapp_bucket = "contoso-webapp-reports-${var.environment}"
  batch_bucket  = "contoso-batch-output-${var.environment}"
}

# ── Web App Reports Bucket (ADR-0002) ─────────────────────────────────────────

resource "aws_s3_bucket" "webapp_reports" {
  bucket = local.webapp_bucket
  tags   = { Name = local.webapp_bucket, Workload = "webapp" }
}

resource "aws_s3_bucket_versioning" "webapp_reports" {
  bucket = aws_s3_bucket.webapp_reports.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "webapp_reports" {
  bucket                  = aws_s3_bucket.webapp_reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "webapp_reports" {
  bucket = aws_s3_bucket.webapp_reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# PDFs → Glacier after 90 days (ADR-0002 lifecycle requirement)
resource "aws_s3_bucket_lifecycle_configuration" "webapp_reports" {
  bucket = aws_s3_bucket.webapp_reports.id
  rule {
    id     = "pdf-to-glacier"
    status = "Enabled"
    filter { prefix = "reports/" }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ── Batch Output Bucket (ADR-0002) ────────────────────────────────────────────

resource "aws_s3_bucket" "batch_output" {
  bucket = local.batch_bucket
  tags   = { Name = local.batch_bucket, Workload = "batch" }
}

resource "aws_s3_bucket_versioning" "batch_output" {
  bucket = aws_s3_bucket.batch_output.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "batch_output" {
  bucket                  = aws_s3_bucket.batch_output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "batch_output" {
  bucket = aws_s3_bucket.batch_output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Reconciliation output retained 7 years for compliance (ADR-0002)
resource "aws_s3_bucket_lifecycle_configuration" "batch_output" {
  bucket = aws_s3_bucket.batch_output.id
  rule {
    id     = "compliance-retention"
    status = "Enabled"
    filter { prefix = "reconciled/" }
    expiration { days = 2555 } # 7 years
  }
}

# ── Read-only IAM policy for internal teams (ADR-0002) ────────────────────────

resource "aws_iam_policy" "reports_readonly" {
  name        = "contoso-reports-readonly-${var.environment}"
  description = "Read-only access to both report buckets for internal teams"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.webapp_reports.arn,
          "${aws_s3_bucket.webapp_reports.arn}/*",
          aws_s3_bucket.batch_output.arn,
          "${aws_s3_bucket.batch_output.arn}/*",
        ]
      }
    ]
  })
}
