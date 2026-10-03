variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-2"
}

variable "bucket_name" {
  type        = string
  description = "적재 대상 버킷. aggregation 과 공유하고 raw/ prefix 로 나눈다"
  default     = "team-neki-log-production"
}

variable "delivery_role_name" {
  type        = string
  description = "infra 루트 모듈이 만든 Firehose 전송 역할. raw/ 밖으로는 쓰지 못한다"
  default     = "team-neki-log-raw-production-firehose-delivery"
}

variable "buffering_interval_seconds" {
  type        = number
  description = "S3 로 내보내기 전 최대 대기 시간. 트래픽이 작아 대부분 이 값이 객체 생성 주기가 된다"
  default     = 300
}
