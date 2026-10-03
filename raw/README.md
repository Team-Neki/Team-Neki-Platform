# raw

원본 로그 토픽입니다. 현재는 앱 클라이언트 로그 하나이며, 결정 근거는 [ADR-0004](../docs/adr/0004-raw-client-log-firehose.md) 에 있습니다.

## 무엇을 만드는가

| 리소스 | 역할 |
|---|---|
| `team-neki-log-raw-production-client-log` | 운영 전송 스트림 |
| `team-neki-log-raw-staging-client-log` | staging 전송 스트림 (단일 환경 원칙의 예외) |
| `/aws/kinesisfirehose/<스트림 이름>` | 전송 실패 로그, 14일 보관 |

적재 경로는 `s3://team-neki-log-production/raw/client-log/env=<env>/year=YYYY/month=MM/day=DD/` 입니다 (UTC 도착 시각, GZIP NDJSON).

전송 역할은 `infra` 루트 모듈 소관이라 여기서는 이름으로 읽기만 합니다. `infra` 가 먼저 적용되어 있어야 plan 이 됩니다.

## 적용

`apply` 는 사람이 plan 을 보고 승인한 뒤에 합니다 (AGENTS.md §7).

```bash
cd raw/infra
terraform init
terraform plan
terraform apply
```

적용 뒤 `client_log_stream_names` 출력값을 Server 의 `aws.firehose.delivery-stream` 과 맞춥니다.

## 확인

```bash
aws firehose describe-delivery-stream --delivery-stream-name team-neki-log-raw-staging-client-log \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'
aws s3 ls s3://team-neki-log-production/raw/client-log/env=staging/ --recursive | tail -3
```
