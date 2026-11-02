locals {
  # 환경마다 스트림, 버킷, 전송 역할이 하나씩이다. 역할은 자기 버킷의 raw/ 에만 쓴다.
  # staging 리소스는 이름 규칙(team-neki-log-<topic>-production-<role>)의 예외다 (ADR-0004).
  client_log = {
    production = {
      stream     = "team-neki-log-raw-production-client-log"
      bucket_arn = "arn:aws:s3:::team-neki-log-production"
      role_name  = "team-neki-log-raw-production-firehose-delivery"
    }
    staging = {
      stream     = "team-neki-log-raw-staging-client-log"
      bucket_arn = aws_s3_bucket.staging.arn
      role_name  = "team-neki-log-raw-staging-firehose-delivery"
    }
  }
}

# 로그 그룹 이름은 전송 역할의 logs:PutLogEvents 범위(/aws/kinesisfirehose/team-neki-log-*)
# 안에 있어야 한다. 밖이면 전송 실패가 기록되지 않고 조용히 사라진다.
resource "aws_cloudwatch_log_group" "client_log" {
  for_each          = local.client_log
  name              = "/aws/kinesisfirehose/${each.value.stream}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "client_log_s3_delivery" {
  for_each       = local.client_log
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.client_log[each.key].name
}

resource "aws_kinesis_firehose_delivery_stream" "client_log" {
  for_each    = local.client_log
  name        = each.value.stream
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.value.role_name}"
    bucket_arn = each.value.bucket_arn

    # 두 prefix 모두 raw/ 아래여야 한다. 전송 역할이 그 밖에는 쓰지 못한다.
    # timestamp 는 S3 객체 안 가장 오래된 레코드의 Firehose 도착 시각이고, custom_time_zone 으로 KST 날짜로 끊는다
    # (두 prefix 모두 적용). 객체 단위라 KST 자정 직후 버퍼 간격만큼 도착한 줄은 전날 폴더에 들어갈 수 있다.
    # 레코드 안의 시각(receivedAt 등)은 UTC 그대로다. 바뀌는 것은 폴더 날짜뿐이다.
    prefix              = "raw/client-log/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "raw/client-log-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    custom_time_zone    = "Asia/Seoul"

    buffering_size     = 5
    buffering_interval = var.buffering_interval_seconds
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.client_log[each.key].name
      log_stream_name = aws_cloudwatch_log_stream.client_log_s3_delivery[each.key].name
    }
  }
}
