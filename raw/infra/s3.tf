# staging 클라이언트 로그 전용 버킷. 운영 버킷(team-neki-log-production)은 aggregation/infra 소관이다.
# Server 미디어, Workflow 처럼 환경을 버킷으로 나눈다 (ADR-0004).
resource "aws_s3_bucket" "staging" {
  bucket = "team-neki-log-staging"
}

resource "aws_s3_bucket_public_access_block" "staging" {
  bucket                  = aws_s3_bucket.staging.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (2023+ AWS 기본값이지만 운영 버킷과 같이 명시)
resource "aws_s3_bucket_server_side_encryption_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
