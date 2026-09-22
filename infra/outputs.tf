output "firehose_delivery_role_arn" {
  description = "전송 스트림을 만들 때 Firehose 에 넘길 역할 ARN"
  value       = aws_iam_role.firehose_delivery.arn
}

output "firehose_s3_destination_prefix" {
  description = "전송 역할이 쓸 수 있는 S3 경로. 이 밖으로는 쓰지 못한다"
  value       = "s3://${var.bucket_name}/${var.firehose_s3_prefix}"
}

output "yapp_policy_arn" {
  description = "yapp 에 붙은 Firehose 구성 정책 ARN"
  value       = aws_iam_policy.yapp_firehose.arn
}
