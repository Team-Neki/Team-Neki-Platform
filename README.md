# Team-Neki-Platform

네키 앱 도메인의 **일간 집계 데이터를 수신·저장**하는 시스템.
GitHub Actions cron이 매일 KST 10시에 GA4 일간 리포트를 정규화 JSON으로 POST 하면, API Gateway → Lambda → S3 경로로 영구 저장한다.

분석/조회/시각화는 명시적 non-goal이며, 별도 모듈/레포가 S3 객체를 직접 소비한다.

> 결정 배경: [ADR-0001](docs/adr/0001-aggregation-storage-on-s3.md)

## 아키텍처

```
GitHub Actions (cron, 10:00 KST)
   ↓ HTTPS POST (Shared Secret URL)
API Gateway (public, ap-northeast-2)
   ↓
Lambda (검증·정규화)
   ↓ PutObject
S3  team-neki-log-production
    └── aggregation/year=YYYY/month=MM/day=DD/ga4-daily-report.json
```

스택: Python 3.13 · Terraform · AWS (API Gateway HTTP API, Lambda arm64, S3, IAM, CloudWatch Logs, Budgets) · 단일 계정 / 단일 리전 / 단일 환경 (prod).

## 레포 구조

토픽 기반 디렉토리. `aggregation`은 현재 유일한 토픽이며, 향후 `raw` 등 추가 시 같은 레벨에 형제로 둔다.
`infra`는 토픽이 아니라 계정 단위 공통 리소스 자리다. Terraform state를 토픽과 나눠 쓴다.

```
.
├── aggregation/                 # 일간 집계 토픽 (Lambda + IaC + 테스트)
│   ├── src/                     # handler.py, JSON Schema
│   ├── tests/                   # pytest
│   ├── infra/                   # Terraform
│   └── README.md                # 컴포넌트 셋업·배포 절차
├── infra/                       # 토픽에 속하지 않는 계정 단위 리소스 (IAM)
├── docs/
│   ├── adr/                     # 의사결정 기록 (최상위 권위)
│   ├── aggregation/             # 토픽별 HLD / LLD
│   ├── conventions/             # commit 컨벤션 등
│   └── plan/roadmap.md          # 진행 상황
├── .github/                     # CI 워크플로, PR 템플릿
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

## 문서 인덱스

의사결정 권위 순서: **ADR > HLD > LLD > 코드 > 컨벤션** ([AGENTS.md §2](AGENTS.md))

### ADR (의사결정)
- [ADR-0001 — Aggregation Storage on S3](docs/adr/0001-aggregation-storage-on-s3.md)
- [ADR-0002 — Lint·Test CI 게이트와 에이전트 자동 정리 hook](docs/adr/0002-lint-and-ci-pipeline.md)

### 토픽 설계
- [HLD: Aggregation](docs/aggregation/hld.md) — 시스템 그림, 컴포넌트 책임
- [LLD: Aggregation](docs/aggregation/lld.md) — API contract, 페이로드 스키마, IaC 명세

### 컨벤션·운영
- [AGENTS.md](AGENTS.md) — 에이전트(사람·AI)가 따라야 할 작업 규칙
- [Commit 컨벤션](docs/conventions/commit-convention.md)
- [PR 템플릿](.github/PULL_REQUEST_TEMPLATE.md)
- [Roadmap](docs/plan/roadmap.md)

## 기여 규칙 (핵심만)

전체 규칙은 [AGENTS.md](AGENTS.md)에 있다. 자주 어기는 항목:

- **토픽 경계를 넘지 마라.** aggregation 작업 중 raw 코드를 미리 만들지 않는다.
- **ADR과 다른 코드는 버그다.** 임의 변경으로 ADR을 우회하지 말고, 먼저 ADR을 갱신한다.
- **IAM 권한·S3 prefix·Public Access Block을 임의 확장하지 마라.** ADR-0001의 보안 모델이 전제다.
- **Commit/PR 제목은 `type(scope): 한국어 제목` + `Refs: ADR-XXXX` trailer.** Scope는 토픽 기반 (`aggregation`, `infra`, `docs`, `ci`, `repo`).
- **CI가 머지 게이트다.** 로컬 통과로 끝내지 말고 `.github/workflows/ci.yml`이 통과해야 한다.

## 비용·운영 가정

- 일 1회 호출 / 페이로드 < 1 MB / 예상 월 비용 < $1
- AWS Budgets 월 $5 한도 (초과 시 알림)
- 가정에 어긋나는 트래픽 패턴이 보이면 [ADR-0001 Re-evaluation Triggers](docs/adr/0001-aggregation-storage-on-s3.md#consequences) 부터 본다.
