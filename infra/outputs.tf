output "firehose_delivery_role_arns" {
  description = "환경별 전송 역할 ARN. 전송 스트림을 만들 때 Firehose 에 넘긴다"
  value       = { for env, role in aws_iam_role.firehose_delivery : env => role.arn }
}

output "firehose_s3_destination_prefixes" {
  description = "환경별로 전송 역할이 쓸 수 있는 S3 경로. 이 밖으로는 쓰지 못한다"
  value       = { for env, d in local.firehose_delivery : env => "s3://${d.bucket}/${var.firehose_s3_prefix}" }
}

output "yapp_policy_arn" {
  description = "yapp 에 붙은 Firehose 구성 정책 ARN"
  value       = aws_iam_policy.yapp_firehose.arn
}
