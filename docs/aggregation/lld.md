# LLD: Aggregation

## 1. Overview

`aggregation` 토픽의 구현 디테일을 다룬다. HLD에서 정의된 컴포넌트(API Gateway / Lambda / S3)의 **인터페이스 명세, 페이로드 contract, 검증 규칙, 운영 디테일, IaC 구조**를 기술한다. 결정 배경은 [ADR-0001](../adr/0001-aggregation-storage-on-s3.md), 시스템 그림은 [HLD](./hld.md) 참조.

## 2. API Contract

### 2.1 Endpoint

```
POST https://{api_id}.execute-api.ap-northeast-2.amazonaws.com/aggregations/ga4-daily-report
```
- Method: `POST`
- Path: `/aggregations/ga4-daily-report`
- Content-Type: `application/json; charset=utf-8`
- Authorization: 없음 (Shared Secret URL 모델)

### 2.2 Request

#### Headers
- `Content-Type: application/json` (필수)
- 그 외 헤더 무시

#### Body Example
```json
{
  "schema_version": "1.0",
  "report_date": "2026-05-24",
  "report_type": "ga4-daily-report",
  "generated_at": "2026-05-25T01:00:00Z",
  "source": { "property_id": "524989384" },
  "events": {
    "session_start": { "count": 123, "users": 123 },
    "first_open": { "count": 45, "users": 45 },
    "map_view": { "count": 100, "users": 80 }
  },
  "dimensions": {
    "map_brand_filter_toggle.brand_name": [
      { "value": "MUSINSA", "count": 10 }
    ],
    "photo_upload.method": [
      { "value": "gallery", "count": 30 },
      { "value": "qr", "count": 5 }
    ]
  }
}
```

### 2.3 Response

#### Success (200)
```json
{
  "status": "stored",
  "object_key": "aggregation/year=2026/month=05/day=24/ga4-daily-report.json",
  "report_date": "2026-05-24"
}
```

#### Error (표준 envelope)
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Schema validation failed",
    "details": {
      "field": "report_date",
      "reason": "does not match format YYYY-MM-DD"
    }
  }
}
```

### 2.4 Error Codes

| HTTP | code | 발생 시점 | Producer 대응 |
|---|---|---|---|
| 400 | INVALID_JSON | body 파싱 실패 또는 Content-Type 부적합 | 페이로드/헤더 수정 |
| 400 | VALIDATION_ERROR | JSON Schema 검증 실패 | 페이로드 수정 |
| 400 | DATE_OUT_OF_RANGE | report_date가 허용 범위 밖 (오늘±7일) | 페이로드 수정 |
| 400 | UNSUPPORTED_SCHEMA_VERSION | major 버전이 1이 아님 | 스키마 마이그레이션 |
| 429 | TOO_MANY_REQUESTS | API GW rate limit 초과 (자동) | exponential backoff 재시도 |
| 500 | STORAGE_ERROR | S3 PutObject 실패 | 5초 후 재시도 |
| 500 | INTERNAL_ERROR | 미처리 예외 | 재시도, 반복 시 운영 알림 |

## 3. Payload Schema

### 3.1 JSON Schema 정의

파일: `aggregation/src/schemas/ga4-daily-report.v1.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "GA4 Daily Report Aggregation v1",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version", "report_date", "report_type",
    "generated_at", "events"
  ],
  "properties": {
    "schema_version": {
      "type": "string",
      "pattern": "^1\\.[0-9]+$"
    },
    "report_date": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
    },
    "report_type": {
      "type": "string",
      "const": "ga4-daily-report"
    },
    "generated_at": {
      "type": "string",
      "format": "date-time"
    },
    "source": {
      "type": "object",
      "additionalProperties": false,
      "required": ["property_id"],
      "properties": {
        "property_id": { "type": "string", "minLength": 1 }
      }
    },
    "events": {
      "type": "object",
      "minProperties": 1,
      "additionalProperties": { "$ref": "#/definitions/event_stat" }
    },
    "dimensions": {
      "type": "object",
      "additionalProperties": {
        "type": "array",
        "items": { "$ref": "#/definitions/dimension_breakdown" }
      }
    }
  },
  "definitions": {
    "event_stat": {
      "type": "object",
      "additionalProperties": false,
      "required": ["count"],
      "properties": {
        "count": { "type": "integer", "minimum": 0 },
        "users": { "type": "integer", "minimum": 0 }
      }
    },
    "dimension_breakdown": {
      "type": "object",
      "additionalProperties": false,
      "required": ["value", "count"],
      "properties": {
        "value": { "type": "string" },
        "count": { "type": "integer", "minimum": 0 }
      }
    }
  }
}
```

### 3.2 필드별 설명

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `schema_version` | string (`^1\.[0-9]+$`) | ✅ | 스키마 버전 (`major.minor`) |
| `report_date` | string (`YYYY-MM-DD`) | ✅ | **KST 기준** 보고 대상 일자 |
| `report_type` | const `ga4-daily-report` | ✅ | 리포트 종류 식별자 |
| `generated_at` | string (ISO 8601 UTC) | ✅ | Producer 페이로드 생성 시각 |
| `source.property_id` | string | ✅ (source 사용 시) | GA4 property ID |
| `events` | object | ✅ | 이벤트별 카운트/유저수. key=이벤트명 |
| `dimensions` | object | ❌ | 이벤트별 디멘션 breakdown. key=`<event>.<field>` |

### 3.3 Schema Versioning 정책

- 형식: `major.minor`
- **Minor 증가** (`1.0` → `1.1`): 하위 호환 (선택 필드 추가 등) → Lambda 그대로 수용
- **Major 증가** (`1.0` → `2.0`): 호환 불가 (필드 제거/타입 변경 등) → Lambda 거부 (`UNSUPPORTED_SCHEMA_VERSION`)
- Major 도입은 별도 ADR로 결정 + 마이그레이션 계획 수립

## 4. S3 Object Spec

### 4.1 Key 구성 규칙
```
aggregation/year={YYYY}/month={MM}/day={DD}/ga4-daily-report.json
```
- 페이로드 `report_date` 파싱 → 제로 패딩
- 같은 `report_date` 재호출 시 동일 키 → 자연 멱등 덮어쓰기

### 4.2 Content-Type / Encoding
- `Content-Type: application/json; charset=utf-8`
- UTF-8 JSON. 압축 없음. trailing newline 없음
- 정규화 없음 (Producer가 보낸 형태 유지)

### 4.3 Object Metadata
Lambda가 PutObject 시 함께 설정 (Terraform 영역 아님 — 런타임 결정):
```
x-amz-meta-schema-version: 1.0
x-amz-meta-report-type: ga4-daily-report
x-amz-meta-generated-at: 2026-05-25T01:00:00Z
```

## 5. Lambda Function Spec

### 5.1 Runtime / Resource

| 항목 | 값 |
|---|---|
| Function name | `team-neki-log-aggregation-production-ingest` |
| Runtime | Python 3.13 |
| Architecture | arm64 (Graviton) |
| Memory | 256 MB |
| Timeout | 10 seconds |
| Reserved Concurrency | 2 |
| Ephemeral storage | 512 MB (default) |
| Log retention | 14 days |

### 5.2 Handler 시그니처

```python
# src/handler.py
import json
import logging
from datetime import date, datetime, timezone, timedelta
from typing import Any

import boto3
import jsonschema

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

with open("schemas/ga4-daily-report.v1.json", encoding="utf-8") as f:
    SCHEMA = json.load(f)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """API Gateway HTTP API v2 proxy event → HTTP response dict."""
    ...
```

### 5.3 환경 변수

| 변수 | 예시 | 설명 |
|---|---|---|
| `S3_BUCKET` | `team-neki-log-production` | 저장 버킷 |
| `S3_PREFIX` | `aggregation` | 객체 키 prefix |
| `REPORT_DATE_MAX_AGE_DAYS` | `7` | report_date 허용 과거 일수 |
| `LOG_LEVEL` | `INFO` | 로그 레벨 |

### 5.4 IAM 권한 (최소 권한)

Role: `team-neki-log-aggregation-production-lambda-role`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3Put",
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::team-neki-log-production/aggregation/*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:ap-northeast-2:*:log-group:/aws/lambda/team-neki-log-aggregation-production-ingest:*"
    }
  ]
}
```
- `s3:PutObject`만 (Get/Delete/List 없음)
- `aggregation/` prefix 한정 (raw 영역 차단)

### 5.5 API Gateway → Lambda Invoke 권한

HTTP API가 Lambda를 호출하려면 별도 권한 부여 필요 (Terraform `aws_lambda_permission`로 관리, §9.3 참조).

## 6. Validation Rules

### 6.1 검증 순서

1. **Content-Type 확인**: `application/json` 아니면 `INVALID_JSON` (400)
2. **JSON 파싱**: 실패 시 `INVALID_JSON` (400)
3. **JSON Schema 검증**: 실패 시 `VALIDATION_ERROR` (400)
4. **schema_version major**: `^1\.` 아니면 `UNSUPPORTED_SCHEMA_VERSION` (400)
5. **report_date 의미 검증**:
   - 오늘(KST) 기준 +1일 이후 미래 → `DATE_OUT_OF_RANGE` (400)
   - 오늘 - 7일 이전 과거 → `DATE_OUT_OF_RANGE` (400)
6. **S3 PutObject**: 실패 시 `STORAGE_ERROR` (500)

### 6.2 에러 details 포맷

| code | details |
|---|---|
| `INVALID_JSON` | `{ reason: "..." }` |
| `VALIDATION_ERROR` | `{ field: "<json-path>", reason: "<jsonschema 메시지>" }` |
| `DATE_OUT_OF_RANGE` | `{ report_date, min, max }` |
| `UNSUPPORTED_SCHEMA_VERSION` | `{ schema_version, supported_major: "1" }` |
| `STORAGE_ERROR` / `INTERNAL_ERROR` | 생략 (CloudWatch Logs로 추적) |

## 7. API Gateway Spec

### 7.1 API 유형
- **HTTP API (v2)**

### 7.2 Route / Integration
```
Route:       POST /aggregations/ga4-daily-report
Integration: AWS_PROXY → Lambda team-neki-log-aggregation-production-ingest
Payload format version: 2.0
Stage:       $default
```

### 7.3 Throttling
- **Rate limit**: 10 req/sec
- **Burst limit**: 20
- **Daily quota**: 적용 안 함 (인증 없는 모델에선 효과적 적용 불가)
- 비용 보호: Lambda Reserved Concurrency = 2, AWS Budgets $5

### 7.4 그 외 설정
- **Authorization**: NONE (Public)
- **CORS**: 비활성화
- **Access Logs**: 비활성화

## 8. Observability Detail

### 8.1 구조화 로그 포맷 (JSON one-line)

```json
{
  "level": "INFO",
  "request_id": "abc-123",
  "stage": "validation_passed",
  "report_date": "2026-05-24",
  "schema_version": "1.0",
  "duration_ms": 23
}
```

### 8.2 단계별 로그

| stage | level | 상황 |
|---|---|---|
| `request_received` | INFO | Lambda 진입 |
| `validation_failed` | WARNING | 검증 실패 (4xx) |
| `validation_passed` | INFO | 검증 통과 |
| `s3_put_success` | INFO | 저장 성공 |
| `s3_put_failed` | ERROR | S3 PUT 실패 (5xx) |
| `unhandled_exception` | ERROR | 미처리 예외 |

### 8.3 메트릭 / 알람
- 별도 커스텀 메트릭/알람 없음 (의도된 단순화)
- CloudWatch Lambda 기본 메트릭 활용 (Invocations / Errors / Duration / Throttles)
- 운영 필요 시점에 알람 추가 (재검토 트리거)

## 9. IaC Module Structure

Terraform 기반. `Team-Neki-Platform/aggregation/` 하위:

```
aggregation/
├── src/
│   ├── handler.py
│   └── schemas/
│       └── ga4-daily-report.v1.json
├── tests/
│   ├── test_handler.py
│   └── fixtures/
│       ├── valid_payload.json
│       └── invalid_payload.json
├── infra/
│   ├── main.tf              # provider, backend
│   ├── variables.tf         # alert_email 등
│   ├── outputs.tf           # API URL, bucket name
│   ├── s3.tf                # 버킷, public access block
│   ├── lambda.tf            # 함수, 코드 패키지(archive_file)
│   ├── apigateway.tf        # HTTP API, route, throttling, lambda_permission
│   ├── iam.tf               # Lambda role/policy
│   ├── logs.tf              # CloudWatch Log Group + retention
│   └── budgets.tf           # AWS Budgets 알림
└── README.md
```

### 9.1 Lambda 코드 패키징 전략

**옵션 A 채택: Terraform이 코드 + 의존성을 zip으로 패키징해 함께 배포**

- 단일 도구·단일 워크플로 (`terraform apply` 한 번에 인프라 + 코드 배포)
- 코드/스키마/`requirements.txt` 중 하나라도 바뀌면 `source_hash`가 바뀌어 Lambda 함수가 자동 갱신됨
- 트레이드오프: 코드만 변경되어도 TF state가 변경됨 (수용)
- 변경 빈도가 늘면 옵션 B(별도 코드 배포 파이프라인)로 마이그레이션 가능

**구현 (`infra/lambda.tf`)**: `handler.py`는 `jsonschema`(+ 네이티브 의존성 `rpds-py`)를 import하는데, 이는 Lambda 런타임 기본 제공이 아니다(`boto3`만 제공). 순수 `archive_file`은 빌드 산출물을 plan 시점에 읽어야 해 의존성 vendor와 양립하지 않으므로, 다음 방식을 쓴다:

- `null_resource.lambda_build`(`local-exec`)가 `src/`를 `build/pkg/`로 복사하고, `pip install --platform manylinux2014_aarch64 --implementation cp --python-version 3.13 --only-binary=:all:`로 arm64/py3.13 대상 wheel을 vendor한 뒤 `build/lambda.zip`으로 압축
- `aws_lambda_function`은 `filename = build/lambda.zip`, `source_code_hash = sha256(소스 입력 해시)`로 참조 (zip 산출물이 아닌 소스 해시 기준 → 클린 체크아웃에서도 plan 가능)
- **apply 환경 요구사항**: `bash`, `python3`(+`pip`), `zip`, 네트워크 (wheel 다운로드). 로컬 Python 버전과 무관 (`--platform`/`--python-version`으로 교차 빌드)

### 9.2 핵심 Terraform 리소스 (요약)

```hcl
# variables.tf
variable "alert_email" {
  type        = string
  description = "AWS Budgets 알림 수신 이메일"
}

# s3.tf
resource "aws_s3_bucket" "main" {
  bucket = "team-neki-log-production"
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# lambda.tf
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name                  = "team-neki-log-aggregation-production-ingest"
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  memory_size                    = 256
  timeout                        = 10
  reserved_concurrent_executions = 2
  handler                        = "handler.lambda_handler"
  role                           = aws_iam_role.lambda.arn
  filename                       = data.archive_file.lambda_zip.output_path
  source_code_hash               = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET                = aws_s3_bucket.main.id
      S3_PREFIX                = "aggregation"
      REPORT_DATE_MAX_AGE_DAYS = "7"
      LOG_LEVEL                = "INFO"
    }
  }
}

# apigateway.tf
resource "aws_apigatewayv2_api" "main" {
  name          = "team-neki-log-aggregation-production"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ingest" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /aggregations/ga4-daily-report"
  target    = "integrations/${aws_apigatewayv2_integration.ingest.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 10
    throttling_burst_limit = 20
  }
}

# Lambda permission for API Gateway to invoke
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# logs.tf
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/team-neki-log-aggregation-production-ingest"
  retention_in_days = 14
}

# budgets.tf
resource "aws_budgets_budget" "monthly" {
  name         = "team-neki-log-aggregation-production-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
```

### 9.3 Terraform Backend

- `tfstate`는 같은 S3 버킷의 `terraform/state/` prefix에 저장 (별도 인프라 의존성 추가 없이 self-host)
- DynamoDB 잠금 미사용 (단일 운영자 가정. 필요 시 추후 도입)

### 9.4 Terraform 외 수동 셋업 (운영자 책임)

Terraform이 처리할 수 없는 항목. 별도 README에 상세 절차 기술 권장:

| 항목 | 위치 | 시점 |
|---|---|---|
| **GA4 property reporting timezone 설정** | Google Analytics 콘솔 | 최초 1회 |
| **GitHub Actions Secret `AGGREGATION_INGEST_URL` 등록** | GitHub repo settings (또는 `gh secret set`) | terraform apply 후, Producer 첫 실행 전 |
| **AWS Budgets 알림 이메일 confirm** | 메일함의 SNS subscription confirmation | 첫 배포 직후 |
| **AWS 계정 자체 셋업** (IAM, MFA 등) | AWS 콘솔 | 최초 1회 |
| **terraform.tfvars의 `alert_email` 값 설정** | 로컬 또는 CI secret | 첫 배포 전 |

`AGGREGATION_INGEST_URL` 값은 `terraform output -raw api_endpoint`. 코드/PR/커밋에 적지 않는다 (Shared Secret URL, §6).

### 9.5 Producer → ingest 전송 동작

1차 Producer(`scripts/ga_daily_report.py`)는 GA4 집계 후 **저장을 우선**해 ingest API로 먼저 POST하고, 그다음 Discord 알림을 보낸다.

- 페이로드: `scripts/ingest.py:build_payload`가 §2.2 스키마로 구성 (디멘션 값 `(not set)` 제외)
- 전송: `post_report`가 429/5xx/네트워크 오류만 지수 backoff 재시도(1·2·4초). 4xx는 페이로드 버그로 보고 즉시 실패(재시도 무의미)
- 실패 격리: ingest가 끝내 실패해도 Discord 리포트는 전송하되 메시지에 저장 실패를 표기하고, job은 non-zero exit로 종료 → GitHub Actions 실패 = 운영 알림(§2.4). `report_date`가 멱등이라 `workflow_dispatch` 재실행이 안전
- 환경변수 `AGGREGATION_INGEST_URL` 필수. 미설정 시 즉시 실패(설정 오류로 간주)

## 10. References
- [ADR-0001: Aggregation Storage on S3](../adr/0001-aggregation-storage-on-s3.md)
- [HLD: Aggregation](./hld.md)
- 코드: `Team-Neki-Platform/aggregation/src/`
- 스키마: `Team-Neki-Platform/aggregation/src/schemas/ga4-daily-report.v1.json`
