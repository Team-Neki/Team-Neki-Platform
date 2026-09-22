terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # aggregation 과 같은 버킷을 쓰되 state 키를 나눈다. 계정 단위 IAM 은 토픽에
  # 종속되지 않으므로 aggregation state 에 섞으면 토픽 하나를 destroy 할 때
  # 계정 권한이 함께 날아간다.
  #
  # 이 버킷은 aggregation 모듈이 만든다. 따라서 aggregation 을 한 번도 apply 하지
  # 않은 계정에서는 이 모듈의 init 이 먼저 실패한다. 순서가 있다는 뜻이고,
  # 버킷을 따로 만들 이유는 아니다.
  backend "s3" {
    bucket = "team-neki-log-production"
    key    = "terraform/state/infra.tfstate"
    region = "ap-northeast-2"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# 사용자는 Terraform 밖에서 만들어졌다. 여기서는 존재를 확인하고 정책만 붙인다.
# 이름이 틀리면 apply 가 아니라 plan 에서 멈춘다.
data "aws_iam_user" "yapp" {
  user_name = var.yapp_user_name
}
