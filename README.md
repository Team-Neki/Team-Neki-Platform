# Team-Neki-Platform

네키 앱 도메인의 데이터를 S3 에 적재하는 시스템. 두 토픽이 서로 독립으로 동작한다.

- **aggregation**: GitHub Actions cron이 매일 KST 10시에 GA4 일간 리포트를 정규화 JSON으로 POST 하면, API Gateway → Lambda → S3 경로로 영구 저장한다.
- **raw**: Server(`POST /api/logs`)가 받은 앱 클라이언트 로그를 Kinesis Data Firehose 가 모아 환경별 버킷의 `raw/client-log/` 에 적재한다.

분석/조회/시각화는 명시적 non-goal이며, 별도 모듈/레포가 S3 객체를 직접 소비한다.

> 결정 배경: [ADR-0001](docs/adr/0001-aggregation-storage-on-s3.md) (aggregation), [ADR-0004](docs/adr/0004-raw-client-log-firehose.md) (raw)

## 아키텍처

aggregation ([HLD](docs/hld/aggregation.md))

```text
GitHub Actions (cron, 10:00 KST)
   ↓ HTTPS POST (Shared Secret URL)
API Gateway (public, ap-northeast-2)
   ↓
Lambda (검증·정규화)
   ↓ PutObject
S3  team-neki-log-production
    └── aggregation/year=YYYY/month=MM/day=DD/ga4-daily-report.json
```

raw ([HLD](docs/hld/raw.md))

```text
iOS / Android
   ↓ HTTPS POST /api/logs (JWT)
Team-Neki-Server (userId·platform·receivedAt 부착, 요청 단위로 묶음)
   ↓ PutRecordBatch
Firehose  team-neki-log-raw-<env>-client-log (버퍼 5MiB / 300초, GZIP)
   ↓ PutObject (환경별 전송 역할, 자기 버킷의 raw/ 만 쓰기)
S3  team-neki-log-production | team-neki-log-staging
    └── raw/client-log/year=YYYY/month=MM/day=DD/*.gz   (UTC 도착 시각)
```

스택: Python 3.13 · Terraform · AWS (API Gateway HTTP API, Lambda arm64, Kinesis Data Firehose, S3, IAM, CloudWatch Logs, Budgets) · 단일 계정 / 단일 리전 / 단일 환경 (prod). 예외: raw 의 staging 스트림·버킷 (ADR-0004).

## 레포 구조

토픽 기반 디렉토리. `aggregation`과 `raw`가 같은 레벨에 형제로 있다.
`infra`는 토픽이 아니라 계정 단위 공통 리소스 자리다. Terraform state를 토픽과 나눠 쓴다.

```text
.
├── aggregation/                 # 일간 집계 토픽 (Lambda + IaC + 테스트)
│   ├── src/                     # handler.py, JSON Schema
│   ├── tests/                   # pytest
│   ├── infra/                   # Terraform
│   └── README.md                # 컴포넌트 셋업·배포 절차
├── raw/                         # 원본 로그 토픽 (실행 코드 없음)
│   ├── infra/                   # Terraform (Firehose 전송 스트림, staging 버킷, ADR-0004)
│   └── README.md                # 리소스 목록·적용 절차
├── infra/                       # 토픽에 속하지 않는 계정 단위 리소스 (IAM)
├── scripts/                     # Producer 스크립트 (GA4 등 일간 리포트 생성, ADR-0003)
├── docs/
│   ├── adr/                     # 의사결정 기록 (최상위 권위)
│   ├── hld/                     # 토픽별 HLD (<topic>.md)
│   ├── lld/                     # 토픽별 LLD (<topic>.md)
│   ├── plan/                    # 로드맵·진행 상황
│   └── spec/                    # 작업 규약 (commit 컨벤션 등)
├── .github/                     # CI·Producer 워크플로, PR 템플릿
├── .claude/                     # 에이전트 hook
├── AGENTS.md                    # 에이전트 작업 규칙 (CLAUDE.md는 심볼릭 링크)
└── pyproject.toml               # ruff·pytest 설정
```

## 빠른 시작

컴포넌트 단위의 개발·테스트·배포 절차는 [`aggregation/README.md`](aggregation/README.md) 참조. 요약하면:

```sh
# 의존성 설치
python3 -m pip install -r aggregation/src/requirements.txt -t aggregation/src/
python3 -m pip install -r aggregation/tests/requirements.txt

# 테스트
pytest

# 린트·포맷
ruff check .
ruff format --check .

# 배포 (사람 승인 후)
cd aggregation/infra
cp terraform.tfvars.example terraform.tfvars   # alert_email 수정
terraform init && terraform plan && terraform apply
```

raw 는 실행 코드 없이 Terraform 만 있다. 적용 순서(`infra` 먼저)와 확인 명령은 [`raw/README.md`](raw/README.md) 참조.

## 문서 인덱스

의사결정 권위 순서: **ADR > HLD > LLD > 코드 > 컨벤션** ([AGENTS.md §2](AGENTS.md))

### ADR (의사결정)
- [ADR-0001 — Aggregation Storage on S3](docs/adr/0001-aggregation-storage-on-s3.md)
- [ADR-0002 — Lint·Test CI 게이트와 에이전트 자동 정리 hook](docs/adr/0002-lint-and-ci-pipeline.md)
- [ADR-0003 — Producer 책임을 본 레포 범위에 포함](docs/adr/0003-producer-in-repo.md)
- [ADR-0004 — Raw Client Log Ingestion via Firehose](docs/adr/0004-raw-client-log-firehose.md)

### 토픽 설계
- [HLD: Aggregation](docs/hld/aggregation.md) — 시스템 그림, 컴포넌트 책임
- [LLD: Aggregation](docs/lld/aggregation.md) — API contract, 페이로드 스키마, IaC 명세
- [HLD: Raw](docs/hld/raw.md) — 클라이언트 로그 적재 구조, 책임 경계, 장애 시 동작
- [raw/README.md](raw/README.md) — raw 리소스 목록, 적용 절차

### 컨벤션·운영
- [AGENTS.md](AGENTS.md) — 에이전트(사람·AI)가 따라야 할 작업 규칙
- [Commit 컨벤션](docs/spec/commit-convention.md)
- [PR 템플릿](.github/PULL_REQUEST_TEMPLATE.md)
- [Roadmap](docs/plan/roadmap.md)

## 기여 규칙 (핵심만)

전체 규칙은 [AGENTS.md](AGENTS.md)에 있다. 자주 어기는 항목:

- **토픽 경계를 넘지 마라.** aggregation 작업 중 raw 코드를 미리 만들지 않는다.
- **ADR과 다른 코드는 버그다.** 임의 변경으로 ADR을 우회하지 말고, 먼저 ADR을 갱신한다.
- **IAM 권한·S3 prefix·Public Access Block을 임의 확장하지 마라.** ADR-0001의 보안 모델이 전제다.
- **Commit/PR 제목은 `type(scope): 한국어 제목` + `Refs: ADR-XXXX` trailer.** Scope는 토픽 기반 (`producer`, `aggregation`, `raw`, `infra`, `docs`, `ci`, `repo`).
- **CI가 머지 게이트다.** 로컬 통과로 끝내지 말고 `.github/workflows/ci.yml`이 통과해야 한다.

## 비용·운영 가정

- aggregation: 일 1회 호출 / 페이로드 < 1 MB / 예상 월 비용 < $1
- raw: 앱 사용량에 비례해 과금 (Firehose 수집 + S3 PUT). 요청 단위로 묶어 레코드 수를 줄인다. 월 Firehose 비용 $1 초과가 재검토 트리거
- AWS Budgets 월 $5 한도 (계정 전체, 초과 시 알림)
- 가정에 어긋나는 패턴이 보이면 [ADR-0001 Re-evaluation Triggers](docs/adr/0001-aggregation-storage-on-s3.md#consequences) (aggregation), [ADR-0004 Re-evaluation Triggers](docs/adr/0004-raw-client-log-firehose.md#re-evaluation-triggers) (raw) 부터 본다.
