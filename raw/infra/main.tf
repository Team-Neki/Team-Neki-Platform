terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # aggregation, infra 와 같은 버킷을 쓰되 state 키를 나눈다 (토픽 단위 state).
  backend "s3" {
    bucket = "team-neki-log-production"
    key    = "terraform/state/raw.tfstate"
    region = "ap-northeast-2"
  }
}

provider "aws" {
  region = var.aws_region
}

# 전송 역할은 infra 루트 모듈이 만든다. 여기서는 이름으로 ARN 을 조합해 쓰기만 한다.
# remote_state 나 data source 로 읽지 않는 것은 infra 를 적용하기 전에도 plan 이 돌게 하기 위해서다.
# 대신 apply 는 infra 가 먼저다 (역할이 없으면 스트림 생성이 실패한다).
data "aws_caller_identity" "current" {}
