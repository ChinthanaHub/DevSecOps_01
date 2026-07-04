# Fix for F-01 / F-02 — six buckets in terraform/aws/s3.tf have no public access block.
# Add one per bucket. Applied alongside the existing bucket resources, not replacing them.

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "financials" {
  bucket = aws_s3_bucket.financials.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "operations" {
  bucket = aws_s3_bucket.operations.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "data_science" {
  bucket = aws_s3_bucket.data_science.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# F-10 fix, same file: financials bucket had no encryption at all, unlike the sibling `logs` bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "financials" {
  bucket = aws_s3_bucket.financials.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs_key.arn # reuse the estate's existing CMK per Module 5's per-workload key policy
    }
  }
}

# F-27 fix: versioning was missing on data/financials, unlike operations/data_science which already have it.
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "financials" {
  bucket = aws_s3_bucket.financials.id
  versioning_configuration {
    status = "Enabled"
  }
}
