output "client_log_stream_names" {
  description = "환경별 전송 스트림 이름. Server 의 aws.firehose.delivery-stream 에 넣는다"
  value       = { for env, stream in aws_kinesis_firehose_delivery_stream.client_log : env => stream.name }
}

output "client_log_s3_prefixes" {
  description = "환경별 적재 경로"
  value       = { for env, _ in local.client_log_streams : env => "s3://${var.bucket_name}/raw/client-log/env=${env}/" }
}
