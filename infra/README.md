# infra

토픽에 속하지 않는 계정 단위 리소스를 관리한다. 현재는 IAM 뿐이다.

`aggregation/infra` 와 state 를 나눠 쓴다. 같은 버킷의 다른 키(`terraform/state/infra.tfstate`)다.
계정 권한이 토픽 state 에 섞이면 토픽 하나를 destroy 할 때 권한까지 같이 날아간다.

## 무엇을 만드는가

| 리소스 | 역할 |
|---|---|
| `team-neki-log-raw-production-firehose-delivery` | Firehose 가 맡아 S3 에 쓰는 전송 역할 |
| `team-neki-log-infra-production-yapp-firehose` | yapp 이 전송 스트림을 구성할 수 있게 하는 정책 |

전송 스트림 자체는 만들지 않는다. 여기서 주는 것은 **구성할 수 있는 권한**까지다.

## 왜 역할을 여기서 만드는가

전송 스트림을 만들려면 역할을 Firehose 에 넘겨야 한다(`iam:PassRole`). 역할 생성까지
yapp 에 열어주면 임의의 권한을 가진 역할을 만들어 자신에게 넘길 수 있다. 권한 상승
통로가 열리는 것이다. 그래서 역할은 관리자가 코드로 만들고, yapp 에게는 **이 역할만,
Firehose 에게만** 넘길 수 있는 권한을 준다.

## 적용

**yapp 자격증명으로는 적용할 수 없다.** 자기에게 권한을 주는 일이라 관리자 자격증명이
필요하다. 최초 1회는 admin 으로 적용한다.

```bash
cd infra
terraform init
terraform plan
terraform apply
```

적용 뒤 `firehose_delivery_role_arn` 을 전송 스트림 정의에 넘긴다.

## 범위를 좁힌 지점

- 전송 역할은 `s3://team-neki-log-production/raw/` 밖으로 쓰지 못한다. `aggregation/` 은
  Lambda 영역이라 전송 역할이 닿으면 안 된다
- yapp 은 이름이 `team-neki-log-` 로 시작하는 전송 스트림만 다룬다
- `iam:PassRole` 은 역할 하나로 못박고 `iam:PassedToService` 조건까지 걸었다

prefix 를 `raw/` 로 잡은 것은 AGENTS.md §4 의 토픽 표에서 원본 로그 수집이 `raw` 이기
때문이다. 다른 토픽에 붙일 거라면 `firehose_s3_prefix` 와 `delivery_role_name` 을 함께
바꾼다.

## 알려진 한계

콘솔에서 전송 스트림을 만들 때 역할 선택 드롭다운은 `iam:ListRoles` 를 요구한다. 이
정책에는 없다. 콘솔로 끝까지 만들려면 ARN 을 직접 입력하거나 `iam:ListRoles` 를 더해야
한다. Terraform 으로 만들면 필요 없다.
