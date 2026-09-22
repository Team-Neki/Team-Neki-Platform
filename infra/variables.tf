variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-2"
}

variable "bucket_name" {
  type        = string
  description = "Firehose 전송 대상 S3 버킷. aggregation 과 같은 버킷을 토픽 prefix 로 나눠 쓴다"
  default     = "team-neki-log-production"
}

variable "firehose_s3_prefix" {
  type        = string
  description = "Firehose 가 쓸 수 있는 S3 prefix. 이 밖은 전송 역할로도 쓰지 못한다"
  default     = "raw/"
}

variable "yapp_user_name" {
  type        = string
  description = "Firehose 파이프라인을 구성할 IAM 사용자"
  default     = "yapp"
}

variable "delivery_stream_prefix" {
  type        = string
  description = "yapp 이 다룰 수 있는 전송 스트림 이름 접두사. 이 접두사 밖의 스트림은 건드리지 못한다"
  default     = "team-neki-log-"
}

variable "delivery_role_name" {
  type        = string
  description = "Firehose 가 맡을 전송 역할 이름"
  default     = "team-neki-log-raw-production-firehose-delivery"
}

variable "yapp_policy_name" {
  type        = string
  description = "yapp 에 붙일 Firehose 구성 정책 이름"
  default     = "team-neki-log-infra-production-yapp-firehose"
}
