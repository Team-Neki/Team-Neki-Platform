# aggregation

일간 집계 데이터 수신·저장 컴포넌트.

- 설계: [HLD](../docs/hld/aggregation.md) · [LLD](../docs/lld/aggregation.md)
- 결정 배경: [ADR-0001](../docs/adr/0001-aggregation-storage-on-s3.md)

## 디렉토리 구조

```
aggregation/
├── src/
│   ├── handler.py                          # Lambda 진입점
│   ├── requirements.txt                    # 런타임 의존성 (jsonschema)
│   └── schemas/
│       └── ga4-daily-report.v1.json        # 입력 페이로드 contract
├── tests/
│   ├── conftest.py
│   ├── requirements.txt                    # 개발 의존성 (pytest, moto)
│   ├── test_handler.py
│   └── fixtures/
│       └── valid_payload.json
├── infra/                                  # Terraform IaC
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf
│   ├── iam.tf
│   ├── logs.tf
│   ├── lambda.tf
│   ├── apigateway.tf
│   ├── budgets.tf
│   └── terraform.tfvars.example
└── README.md
```

## 로컬 개발

### 의존성 설치

```sh
# 런타임 의존성을 src/에 벤더링 (Terraform archive_file이 zip에 포함)
python3 -m pip install -r src/requirements.txt -t src/

# 개발 의존성
python3 -m pip install -r tests/requirements.txt
```

### 테스트

```sh
cd tests && python3 -m pytest -v
```

## 배포 (Terraform)

### 사전 준비

- AWS 자격증명 설정 (etc/ 디렉토리이므로 koosco 계정 사용)
- `terraform.tfvars` 작성

```sh
cd infra
cp terraform.tfvars.example terraform.tfvars
# alert_email 값을 본인 이메일로 수정
```

### 첫 배포

```sh
cd infra
terraform init
terraform plan
terraform apply
```

배포 후 출력되는 `api_endpoint` 값을 GitHub Actions Secret (예: `NEKI_LOG_INGEST_URL`)으로 등록한다.

### State 마이그레이션 (선택)

첫 배포로 S3 버킷이 생성된 후, Terraform state를 S3로 옮기려면 `main.tf`의 `backend "s3"` 블록 주석을 해제하고:

```sh
terraform init -migrate-state
```

## 수동 셋업 절차 (Terraform 외)

| 항목 | 위치 | 시점 |
|---|---|---|
| GA4 property reporting timezone (KST) | Google Analytics 콘솔 | 최초 1회 |
| AWS Budgets 알림 이메일 confirm | 이메일함의 SNS subscription 확인 링크 | 첫 apply 직후 |
| GitHub Actions Secret 등록 (API URL) | GitHub repo settings | apply 후 |
| AWS 계정 셋업 (IAM, MFA 등) | AWS 콘솔 | 최초 1회 |

## Producer 측 변경 가이드

GA4 일간 리포트를 생성하는 GitHub Actions workflow에서, 정규화된 JSON 페이로드를 본 endpoint로 POST해야 한다. 자세한 페이로드 스키마는 `src/schemas/ga4-daily-report.v1.json` 또는 [LLD §3](../docs/lld/aggregation.md#3-payload-schema) 참조.

예시:

```python
import os
import requests

INGEST_URL = os.environ["NEKI_LOG_INGEST_URL"]

payload = {
    "schema_version": "1.0",
    "report_date": "2026-05-24",
    "report_type": "ga4-daily-report",
    "generated_at": "2026-05-25T01:00:00Z",
    "source": {"property_id": "524989384"},
    "events": {...},
    "dimensions": {...},
}

resp = requests.post(INGEST_URL, json=payload, timeout=10)
resp.raise_for_status()
```
