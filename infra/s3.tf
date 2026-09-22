# 계정의 S3 버킷. 전부 콘솔이나 다른 레포에서 만들어진 것을 가져온 것이다.
# 신규 생성이 아니므로 설정은 실물과 한 글자도 달라서는 안 된다. 다르면 apply 가
# 운영 버킷의 설정을 바꾼다. imports.tf 와 짝이며, plan 이 No changes 여야 맞다.
#
# 공통은 전부 같다. SSE-S3(AES256), public access block 4개 전부 차단, 버킷 정책
# 없음, lifecycle 없음, 버저닝 미설정. 다른 것은 CORS 와 ownership, 태그,
# bucket key 뿐이라 맵에 그것만 담는다.
#
# 버저닝은 선언하지 않는다. 실물이 미설정 상태라 Disabled 로 선언하면 apply 가
# 설정을 새로 거는 변경이 된다. 없는 것을 없다고 쓰는 방법이 Terraform 에는 없다.
locals {
  buckets = {
    "yapp-neki-ap-northeast-2" = {
      bucket_key = true
      purpose    = "Server prod 미디어"
      ownership  = "BucketOwnerEnforced"
      cors       = true
      tags       = {}
    }
    "yapp-neki-staging-ap-northeast-2" = {
      bucket_key = false
      purpose    = "Server staging 미디어"
      # 이 버킷만 Preferred 다. 예전 모듈이 ACL 을 걸려고 그렇게 뒀다.
      # 실물이 그러하므로 그대로 가져온다. 정리는 별도 건이다.
      ownership = "BucketOwnerPreferred"
      cors      = true
      tags = {
        Project     = "YAPP"
        Environment = "staging"
        Purpose     = "Public Image Storage"
        ManagedBy   = "Terraform"
        Preset      = "private"
        Name        = "yapp-neki-staging-ap-northeast-2"
      }
    }
    "staging-team-neki-workflow" = {
      bucket_key = true
      purpose    = "Workflow 수집 적재 (staging)"
      ownership  = "BucketOwnerEnforced"
      cors       = false
      tags       = {}
    }
    "prod-team-neki-workflow" = {
      bucket_key = true
      purpose    = "Workflow 수집 적재 (prod)"
      ownership  = "BucketOwnerEnforced"
      cors       = false
      tags       = {}
    }
    "team-neki-sprint" = {
      bucket_key = true
      purpose    = "Sprint 앱 첨부 저장소"
      ownership  = "BucketOwnerEnforced"
      cors       = false
      tags       = {}
    }
  }

  cors_buckets = { for name, b in local.buckets : name => b if b.cors }
}

resource "aws_s3_bucket" "imported" {
  for_each = local.buckets

  bucket = each.key
  tags   = each.value.tags
}

resource "aws_s3_bucket_public_access_block" "imported" {
  for_each = local.buckets

  bucket                  = aws_s3_bucket.imported[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "imported" {
  for_each = local.buckets

  bucket = aws_s3_bucket.imported[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    # 실물 값을 그대로 쓴다. 생략하면 Terraform 이 꺼버리는 변경이 된다.
    # 2023 년 이후 만든 버킷은 기본이 true 라 staging 하나만 false 다.
    bucket_key_enabled = each.value.bucket_key
  }
}

resource "aws_s3_bucket_ownership_controls" "imported" {
  for_each = local.buckets

  bucket = aws_s3_bucket.imported[each.key].id

  rule {
    object_ownership = each.value.ownership
  }
}

# 미디어 버킷만 CORS 가 있다. 브라우저가 presigned URL 로 직접 올리기 때문이다.
resource "aws_s3_bucket_cors_configuration" "imported" {
  for_each = local.cors_buckets

  bucket = aws_s3_bucket.imported[each.key].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST", "GET", "HEAD", "PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
