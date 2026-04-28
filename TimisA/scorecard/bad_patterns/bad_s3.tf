# BAD PATTERN: S3 bucket with public access, no versioning, no encryption.
# All three should be flagged.

resource "aws_s3_bucket" "bad_public" {
  bucket = "contoso-reports-public"
  # Missing tags
}

resource "aws_s3_bucket_public_access_block" "bad" {
  bucket = aws_s3_bucket.bad_public.id

  # BAD: all set to false — bucket is publicly accessible
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# BAD: ACL explicitly set to public-read
resource "aws_s3_bucket_acl" "bad" {
  bucket = aws_s3_bucket.bad_public.id
  acl    = "public-read"
}

# No aws_s3_bucket_versioning — versioning disabled by default
# No aws_s3_bucket_server_side_encryption_configuration — no encryption
