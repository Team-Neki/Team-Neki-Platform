locals {
  # 키는 S3 경로의 env= 값, 값은 스트림 이름.
  # staging 은 이름 규칙(team-neki-log-<topic>-production-<role>)의 예외다 (ADR-0004).
  client_log_streams = {
    production = "team-neki-log-raw-production-client-log"
    staging    = "team-neki-log-raw-staging-client-log"
  }
}

# 로그 그룹 이름은 전송 역할의 logs:PutLogEvents 범위(/aws/kinesisfirehose/team-neki-log-*)
# 안에 있어야 한다. 밖이면 전송 실패가 기록되지 않고 조용히 사라진다.
resource "aws_cloudwatch_log_group" "client_log" {
  for_each          = local.client_log_streams
  name              = "/aws/kinesisfirehose/${each.value}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "client_log_s3_delivery" {
  for_each       = local.client_log_streams
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.client_log[each.key].name
}

resource "aws_kinesis_firehose_delivery_stream" "client_log" {
  for_each    = local.client_log_streams
  name        = each.value
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = data.aws_iam_role.firehose_delivery.arn
    bucket_arn = "arn:aws:s3:::${var.bucket_name}"

    # 두 prefix 모두 raw/ 아래여야 한다. 전송 역할이 그 밖에는 쓰지 못한다.
    # timestamp 는 Firehose 도착 시각(UTC)이다. KST 파티션은 dynamic partitioning 비용이 들어 쓰지 않는다.
    prefix              = "raw/client-log/env=${each.key}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "raw/client-log-errors/env=${each.key}/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

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
