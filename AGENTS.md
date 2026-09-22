# AGENTS.md

이 파일은 AI 에이전트(Claude Code, Codex, 기타)가 Team-Neki-Platform 레포에서 작업할 때 따라야 할 규칙이다. **CLAUDE.md는 이 파일의 심볼릭 링크다 — 이 파일만 수정한다.**

명령형으로 적혀 있다. 지키지 않을 합리적 사유가 있으면 PR 본문에 명시한다.

## 1. Repo 한 줄 요약

Team-Neki-Platform는 네키 앱 도메인의 **일간 집계 데이터를 생성·수신·저장**하는 시스템이다. Producer(GitHub Actions cron + Python) → API Gateway → Lambda → S3. Terraform IaC. Python 3.13. 단일 AWS 계정, 단일 리전(ap-northeast-2), 단일 환경(prod). 분석/조회/시각화는 **명시적 non-goal**이고 별도 모듈이 처리한다.

상세 배경: `docs/adr/0001-aggregation-storage-on-s3.md` (저장 아키텍처), `docs/adr/0003-producer-in-repo.md` (Producer 책임 위치).

## 2. 의사결정 우선순위

충돌 시 위가 이긴다.

1. **ADR** (`docs/adr/`) — 결정의 최상위 권위
2. **HLD** (`docs/<topic>/hld.md`) — 시스템 그림과 컴포넌트 책임
3. **LLD** (`docs/<topic>/lld.md`) — 인터페이스/검증/IaC 디테일
4. **코드** — 실제 동작
5. **이 문서 / 컨벤션** — 작업 방식

**원칙**: 코드가 ADR과 다르면 **버그**다. ADR을 바꾸려면 새 ADR을 쓰거나 기존 ADR의 Status를 변경한다. 임의 코드 변경으로 ADR을 우회하지 마라.

LLD/HLD가 실제와 어긋난다면, 같은 PR에서 문서를 함께 갱신한다. "나중에 고침"으로 두지 마라.

## 3. 컨벤션 (단일 참조)

다른 문서에 흩어두지 않고 이 표에서 모두 링크한다.

| 영역 | 위치 |
|---|---|
| Commit 메시지 | `docs/conventions/commit-convention.md` |
| PR 형식 | `.github/PULL_REQUEST_TEMPLATE.md` |
| ADR 작성 (구조/번호 규칙) | `docs/adr/0001-aggregation-storage-on-s3.md` 양식 참조 |
| 도메인 용어 | 본 문서 §4 |
| 코드 스타일 (ruff lint + format) | `pyproject.toml` (`[tool.ruff]`) |
| CI 게이트 | `.github/workflows/ci.yml` |
| Claude 자동 정리 hook | `.claude/settings.json` + `.claude/hooks/ruff-on-edit.sh` |
| 위 3개 결정 근거 | `docs/adr/0002-lint-and-ci-pipeline.md` |

**핵심 요약 (위반 빈발 항목)**:
- Commit: `type(scope): 한국어 제목` + 본문 한국어 + `Refs: ADR-XXXX` trailer
- Scope는 **토픽 기반** (`producer`, `aggregation`, `raw`, `infra`, `docs`, `ci`, `repo`). 디렉토리명 아님
- Breaking change는 type 뒤 `!` 표기 + `BREAKING CHANGE:` 본문
- PR 제목 = 그대로 squash commit이 된다. PR 제목도 commit 포맷을 따라라

## 4. 도메인 용어 (헷갈리지 마라)

| 용어 | 의미 |
|---|---|
| **aggregation** | 일간 집계 데이터(현재 GA4 일간 리포트). raw와 **완전 독립**된 토픽 |
| **raw** | 원본 로그 (현 시점 미도입, 향후 ADR로 추가) |
| **Producer** | 일간 집계 데이터를 생성해 본 시스템에 공급하는 컴포넌트. 현재 1차 Producer는 GitHub Actions cron + Python (`scripts/ga_daily_report.py`, `.github/workflows/daily-ga-report.yml`). **본 레포 책임** (ADR-0003) |
| **report_date** | 보고 대상 일자 (KST 기준). S3 경로 `day=` 값과 동일 |
| **generated_at** | Producer가 페이로드를 만든 시각 (ISO 8601 UTC) |
| **schema_version** | 페이로드 contract 버전 (`major.minor`). minor=backward compat, major=break |
| **topic** | 데이터 책임 단위(`aggregation`, `raw`). scope/디렉토리/IAM prefix 모두 이 단위로 정렬 |

리소스 네이밍은 항상 `team-neki-log-<topic>-production-<role>`. 버킷만 예외 (`team-neki-log-production`, 토픽 공유).

**접두사가 `team-neki-log-`인 것은 오타가 아니다.** 저장소는 Team-Neki-Platform 으로
이름이 바뀌었지만 AWS 리소스 이름은 그대로 둔다. 이름을 맞추려고 바꾸면 rename 이
아니라 재생성이다. 버킷 이름은 변경 자체가 불가능하고, 그 버킷은 집계 데이터와
Terraform state 를 같이 담고 있어 destroy 대상이 되면 자기 state 를 지우게 된다.
Lambda, IAM role, 로그 그룹도 이름을 바꾸면 교체된다. 옮기려면 신규 버킷 생성 +
데이터 복사 + state 마이그레이션을 따로 계획해야 한다.

## 5. 트래픽/운영 패턴 (이 가정 위에서 결정됨)

이 가정이 깨지면 ADR을 다시 본다. 가정에 어긋난 코드를 함부로 추가하지 마라.

- **호출 빈도**: 일 1회 (cron 10:00 KST). 분당 수십 건 이상이면 수신 패턴 재검토
- **페이로드 크기**: < 1 MB
- **타임존**: GA4 reporting timezone = KST 전제. UTC 00:00–09:00 영역으로 cron 이동 시 KST 일자 계산 코드 수정 필수
- **멱등성**: 같은 `report_date` 재호출 = 같은 S3 키 덮어쓰기. **Versioning OFF, 의도된 트레이드오프**. "안전을 위해 versioning을 켜자" 같은 PR을 만들지 말고 먼저 ADR을 갱신해라
- **단일 운영자 가정**: Terraform state는 S3 self-host, DynamoDB lock 없음. 동시 apply 하지 마라

## 6. 보안 / 운영 금지사항

- API URL, AWS Access Key, GitHub Secret 값을 코드/주석/PR 본문/커밋 메시지 어디에도 적지 마라. 노출 시 즉시 회전
- **Public Access Block 해제 금지**. 외부 소비자도 IAM 경로로 접근한다
- **IAM 권한 확장 금지**. Lambda role은 `s3:PutObject` + 로그만. Get/List/Delete 절대 추가하지 마라
- **`aggregation/` prefix 밖에 쓰지 마라**. raw는 별도 IAM/Lambda
- **AWS Budgets $5 한도**를 의식해라. 예상 비용이 이를 넘기는 변경이면 PR 본문 **Operational impact**에 명시
- 외부 비밀(.tfvars, credentials)을 `.gitignore`에서 빼지 마라
- `terraform destroy`는 절대 하지 마라 (S3 데이터 영구 소실)

## 7. 검증 / 커밋 흐름

작업 → PR → squash merge 흐름 전반에서 지켜라.

1. **변경 전**: 영향받는 ADR/HLD/LLD 섹션을 먼저 읽는다. 충돌이 보이면 문서부터 갱신할지 묻는다
2. **구현 중**: 토픽 경계를 넘지 마라 (aggregation 작업 중 raw 코드를 미리 만들지 않음)
3. **린트**: `ruff check .` + `ruff format --check .` 통과. 에이전트 편집은 `.claude/hooks/ruff-on-edit.sh`가 자동 정리하지만 최종 책임은 PR 작성자
4. **테스트**: `aggregation/tests/`의 pytest 통과 + 변경된 검증 규칙은 fixture 추가
5. **Infra 변경**: `terraform fmt -recursive` + `terraform validate` 후 `terraform plan`을 로컬에서 돌려 결과를 PR 본문에 붙인다. `apply`는 사람이 명시 승인 후
6. **CI**: `.github/workflows/ci.yml`이 위 3·4·5를 PR에서 다시 돌린다. 이게 머지 게이트다 — 로컬 통과로 끝나지 마라
7. **커밋**: `docs/conventions/commit-convention.md` 그대로. `Refs:` 빠뜨리지 마라
8. **PR**: `.github/PULL_REQUEST_TEMPLATE.md`의 모든 섹션을 채운다. "없음"으로 비울 수는 있지만 섹션 자체를 지우지 마라
9. **AI 협업 표시**: 의미 있는 협업이었으면 `Co-Authored-By:` trailer 적는다. 자동 삽입 강제 아님. AI 단독 생성을 인간 작업으로 위장하지 마라

## 8. 모를 때

가정해서 코드를 만들지 말고:
- 사용자에게 묻거나
- ADR/HLD/LLD를 다시 인용하면서 모순을 지적하라

특히 다음은 **반드시 확인**:
- 새 토픽 도입 (raw 등) → ADR 필요
- 페이로드 schema major 변경 → ADR 필요
- IAM 권한 확장 → ADR 필요
- AWS 비용 모델이 바뀌는 신규 리소스 → 사전 합의 필요
