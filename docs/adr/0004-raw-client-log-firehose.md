# ADR-0004: Raw Client Log Ingestion via Firehose

## Status
Proposed (2026-10-04)

## Context and Problem Statement

iOS·Android 앱 로그를 영구 저장할 필요가 생겼습니다. Server(Team-Neki-Server)는 `POST /api/logs` 로 앱 로그를 배치로 받아 사용자 인증(JWT)을 마친 뒤 Kinesis Firehose 로 넘깁니다 (Sprint BACKEND-166, Team-Neki-Server#334). Firehose 를 S3 로 잇는 전송 역할과 yapp 의 스트림 구성 권한은 BACKEND-125 에서 만들었지만, 전송 스트림은 아직 없습니다.

이 ADR 은 AGENTS.md §4 에서 "향후 ADR로 추가" 로 남겨 둔 `raw` 토픽을 도입하고, 클라이언트 로그를 **어떤 경로로, 어떤 단위로, 어디에** 적재할지 정합니다.

## Goals
- 앱 로그 원본을 S3 에 잃지 않고 쌓기 (분석은 별도 모듈 책임)
- 운영 부담 0 에 가까운 관리형 구성 (Lambda 코드 없음)
- 계정 Budgets $5 안에서 운영
- Server staging 에서 배포 전 적재까지 검증 가능

## Non-Goals
- 실시간 조회·알림·대시보드
- 스키마 강제 (로그 원소는 자유 JSON)
- 분석용 포맷 변환 (Parquet 등)

## Decision Drivers
- 비용, 특히 Firehose 의 레코드 단위 과금 (레코드마다 5KB 로 올림)
- 단순성 (컴포넌트 수, 코드 유무)
- 기존 권한 경계 재사용 (BACKEND-125 의 전송 역할은 `raw/` 만 쓸 수 있음)
- aggregation 과의 독립 (토픽 경계)

## Considered Options

### 수신 경로

- **Server → Firehose Direct PUT → S3 ★ 선택**
  인증은 이미 Server 가 합니다. Firehose 가 버퍼링과 S3 객체 생성을 맡으므로 이 레포에 코드가 생기지 않습니다. Server 는 BACKEND-125 정책으로 `team-neki-log-*` 스트림에 `PutRecordBatch` 할 수 있습니다.
- Server → S3 `PutObject` 직접
  요청마다 작은 객체가 생기고, 묶으려면 Server 가 버퍼를 들고 있어야 합니다. Server 에 `raw/` 쓰기 권한을 새로 줘야 해서 IAM 확장(ADR 대상)이 됩니다.
- 앱 → API Gateway → Lambda → S3 (aggregation 방식)
  일 1회 호출을 전제로 만든 경로라 앱 트래픽에 맞지 않습니다. 사용자 인증을 Lambda 에서 다시 구현해야 합니다.
- 앱 → Firehose 직접 (Cognito 자격증명)
  기기에 AWS 자격증명을 내려야 하고, Server 가 붙이는 userId 를 신뢰할 수 없게 됩니다.

### 레코드 단위

Firehose Direct PUT 은 레코드마다 5KB 단위로 올려 과금합니다 (3KB 레코드는 5KB, 12KB 레코드는 15KB). 앱 로그 한 줄은 수백 바이트이므로 단위를 어떻게 잡느냐가 비용을 좌우합니다.

- 로그 1건 = 레코드 1건
  구현이 가장 단순하지만, 400B 로그도 5KB 로 과금되어 실제 바이트의 약 12배를 냅니다.
- **요청 1건의 로그를 NDJSON 으로 이어 붙여 레코드 1건 ★ 선택 (레코드 상한 1,000KiB 를 넘으면 나눔)**
  S3 에 쌓이는 결과는 같습니다 (Firehose 는 레코드를 이어 붙여 객체를 만들고, 줄바꿈은 각 줄 끝에 있음). 과금은 실제 바이트에 가까워집니다.

### staging 처리

AGENTS.md 는 단일 환경(prod)을 전제로 하지만, Server 는 staging 에서 배포 전 검증을 합니다.

- **staging 전용 스트림 ★ 선택**
  같은 버킷에서 `env=` 파티션으로 나눕니다. 운영 원본에 staging 데이터가 섞이지 않고, staging 에서 S3 적재까지 확인할 수 있습니다. 스트림·로그 그룹이 한 벌 더 생기지만 유휴 비용은 0 입니다.
- prod 스트림 공유
  리소스는 적지만 운영 원본에 staging 로그가 섞여 조회할 때마다 걸러야 합니다.
- staging 미적재 (fake)
  가장 단순하지만 S3 적재를 prod 에서 처음 확인하게 됩니다.

### 포맷과 압축
- **NDJSON + GZIP ★ 선택**: 로그 원소가 자유 JSON 이라 스키마가 필요한 변환은 맞지 않습니다. GZIP 은 텍스트 로그를 크게 줄이고 Athena 가 그대로 읽습니다. 사람이 열어 볼 때 `gunzip` 이 필요하다는 불편이 있습니다.
- Parquet 변환: Glue 스키마가 필요하고 GB 당 $0.022 가 추가됩니다. 스키마가 정해지면 다시 봅니다.

### 파티션
- **Firehose 기본 timestamp prefix ★ 선택**: 도착 시각(UTC) 기준 `year=/month=/day=`. 추가 비용이 없습니다.
- Dynamic partitioning (KST 기준이나 필드 기준): GB 당 $0.027 와 객체 1,000개당 $0.0066 이 붙습니다. aggregation 의 KST 일자 규칙과 맞추는 이점보다 비용이 큽니다.

## Decision

### 아키텍처

```text
iOS / Android
   -> HTTPS POST /api/logs (JWT)
Team-Neki-Server  (userId·platform·receivedAt 부착, NDJSON 묶음)
   -> PutRecordBatch
Firehose  team-neki-log-raw-<env>-client-log   (버퍼 5MiB / 300초, GZIP)
   -> PutObject (전송 역할, raw/ 만 쓰기)
S3  team-neki-log-production
    raw/client-log/env=<env>/year=YYYY/month=MM/day=DD/<firehose 객체>.gz
```

### 저장 구조
- **버킷**: `team-neki-log-production` (aggregation 과 공유, prefix 로 분리)
- **경로**: `raw/client-log/env=<production|staging>/year=YYYY/month=MM/day=DD/`
- **실패 경로**: `raw/client-log-errors/env=<env>/<error-output-type>/year=YYYY/month=MM/day=DD/`
- **날짜 기준**: Firehose 도착 시각, UTC (aggregation 의 KST 와 다름)
- **포맷**: NDJSON, GZIP
- **Lifecycle**: 없음 (보관량 재검토 트리거 참고)

### 레코드 contract (Server 소유)
- 한 줄 = 앱 로그 1건: `{"userId": <Long>, "platform": "IOS|ANDROID", "receivedAt": "<ISO 8601 UTC>", "log": {<앱이 보낸 JSON 그대로>}}`
- `appVersion` 등 앱 정보는 `log` 안에 있음 (로그 발생 시점 값)
- Firehose 레코드 1건 = 요청 1건의 줄 묶음 (1,000KiB 초과 시 분할)

### 리소스 네이밍

| 리소스 | 이름 |
|---|---|
| 전송 스트림 (prod) | `team-neki-log-raw-production-client-log` |
| 전송 스트림 (staging) | `team-neki-log-raw-staging-client-log` |
| 로그 그룹 | `/aws/kinesisfirehose/<스트림 이름>` (14일 보관) |
| 전송 역할 (기존) | `team-neki-log-raw-production-firehose-delivery` |
| Terraform | `raw/infra`, state `terraform/state/raw.tfstate` |

> staging 스트림은 `team-neki-log-<topic>-production-<role>` 규칙의 예외입니다. 전송 역할은 환경을 나누지 않고 하나를 같이 씁니다 (쓸 수 있는 범위가 `raw/` 로 같음).

### 비용 (서울 리전, 2026-10 공개 가격)

| 항목 | 단가 | 앱 로그 100만 건/월 (평균 400B) |
|---|---|---|
| Firehose 수집, 로그 1건 = 레코드 1건 | $0.036/GB, 레코드당 5KB 올림 | 약 5GB 과금, 약 $0.18 |
| Firehose 수집, 요청 단위 묶음 (선택) | 같음 | 약 0.4GB 과금, 약 $0.02 |
| S3 PUT (300초 버퍼, 스트림 2개 상한) | $0.0045 / 1,000건 | 최대 약 17,000건, 약 $0.08 |
| S3 저장 (GZIP) | $0.025/GB-월 | 무시할 수준 |

2026-10 계정 Budgets 는 실제 $1.11, 예측 $1.20 입니다 (한도 $5, 계정 전체). 요청 단위로 묶으면 월 수억 건까지 한도 안입니다.

## Consequences

### Positive
- 이 레포에 실행 코드 없이 관리형 서비스만으로 적재
- 유휴 비용 0, 사용량 비례 과금
- 운영 원본과 staging 이 `env=` 로 분리되어 Server 가 배포 전 적재를 검증 가능
- aggregation 과 state·경로·역할 모두 독립

### Negative / Risks
- 단일 환경 원칙의 첫 예외 (raw 의 staging 스트림)
- 날짜 파티션이 UTC 라 KST 일자 조회 시 앞뒤 날짜를 함께 읽어야 함
- 로그 원소가 자유 JSON 이라 앱이 개인정보(이메일, 토큰 등)를 넣어도 막지 못함. 앱 측 규칙으로 관리
- Server 의 재전송(at-least-once)으로 중복 줄이 생길 수 있음
- Lifecycle 이 없어 보관량이 계속 늘어남

### Re-evaluation Triggers
- **월 Firehose 비용이 $1 초과** 또는 Budgets 80% 알림 → 레코드 묶음 단위, 버퍼, 샘플링 재검토
- **로그에 개인정보 포함 필요** → 접근 통제·보관 기간 정책을 별도 ADR 로
- **raw/ 보관량 100GB 초과** → Lifecycle (aggregation 버킷 설정이므로 해당 state 와 함께)
- **분석 스키마 확정** → Parquet 변환 재검토
- **KST 일자 파티션 필요** → dynamic partitioning 비용과 비교

## References
- ADR-0001 (저장소 S3, "raw 도입 시 별도 인프라 + raw/ prefix")
- Sprint BACKEND-173 (이 ADR), BACKEND-125 (전송 역할), BACKEND-166 (Server 엔드포인트)
- Team-Neki-Server#334 (`POST /api/logs`)
- Amazon Data Firehose 가격 (레코드당 5KB 올림 과금)
