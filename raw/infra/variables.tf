variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-2"
}

variable "buffering_interval_seconds" {
  type        = number
  description = "S3 로 내보내기 전 최대 대기 시간. 트래픽이 작아 대부분 이 값이 객체 생성 주기가 된다"
  default     = 300
}
