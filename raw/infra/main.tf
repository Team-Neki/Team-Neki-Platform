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

# 전송 역할은 infra 루트 모듈이 만든다 (BACKEND-125). 여기서는 이름으로 찾아 쓰기만 한다.
# infra state 를 remote_state 로 읽지 않는 것은 state 사이에 순서 의존을 만들지 않기 위해서다.
data "aws_iam_role" "firehose_delivery" {
  name = var.delivery_role_name
}
