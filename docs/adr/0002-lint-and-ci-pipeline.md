# ADR-0002: Lint·Test CI 게이트와 에이전트 자동 정리 hook 도입

## Status
Accepted (2026-05-26)

## Context and Problem Statement

Team-Neki-Platform는 단일 운영자(AGENTS.md §5)가 관리하는 작은 레포지만, **AI 에이전트(Claude Code, Codex 등)도 1급 기여자**로 가정한다(AGENTS.md 1줄 요약). 이 가정 위에서 다음 두 가지가 동시에 사실이다.

1. **머지 게이트가 없다.** PR 시점에 컨벤션·테스트 위반을 잡아주는 자동 검증이 없어, AGENTS.md §7의 "테스트 통과" 항목이 사람 검토에만 의존한다.
2. **AGENTS.md §3의 "코드 스타일" 항목이 TBD다.** 어떤 도구를 사용할지 결정한 적이 없어, 에이전트마다 다른 스타일을 만들 위험이 있다.

본 ADR은 **(a) 어떤 lint·test 도구를, (b) 어디서(CI/hook), (c) 어떤 범위로 적용할지** 결정한다.

## Goals
- AGENTS.md §3의 TBD 해소 (코드 스타일 단일 도구 결정)
- PR 머지 전 자동 게이트 (lint, test, terraform validate)
- 에이전트가 만든 사소한 스타일 잡음(import 정렬, 줄 길이 등)을 사람 리뷰 전에 자동 정리
- 최소 의존성 / 단일 운영자 부담 최소화

## Non-Goals
- pre-commit 프레임워크 도입 (1인 운영자 환경에서 ROI 낮음)
- 타입체크(mypy/pyright) 도입 (현 handler.py 규모에서 ROI 낮음, 별도 ADR로 재검토)
- CI에서 `terraform plan` 실행 (AGENTS.md §7: plan은 로컬 + PR 본문 첨부 운영)
- 보안 스캐너(Snyk/Dependabot/CodeQL) 도입 (별도 ADR)
- 멀티 Python 버전 매트릭스 (Lambda runtime이 py313로 고정)

## Decision Drivers

- **단일 운영자 운영 부담**: 설정 파일 수, 매번 기억해야 할 명령 수
- **에이전트 친화성**: 에이전트가 빠르게 self-correct할 수 있는 도구
- **속도**: PR 회전 시간에 미치는 영향
- **AGENTS.md와의 정합성**: §3 컨벤션 표·§7 검증 흐름과 자연스럽게 합쳐지는지

## Considered Options

### 린트·포맷 도구

| 후보 | 평가 |
|---|---|
| **ruff** | lint + format + import 정렬 단일 바이너리. Rust 구현으로 매우 빠름. 설정 1개. ⭕ |
| black + flake8 + isort | 전통적 조합. 설정 3개, 명령 3개. 속도도 ruff 대비 느림. |
| black 단독 (포맷만) | lint 규칙 부재 — `import *`, unused import 등 검출 못 함. |
| pylint | 정확도 높지만 느리고 false positive 많음. 단일 운영자 부담 큼. |

### 테스트 러너
- pytest 이미 사용 중. 변경 없음.

### CI 플랫폼
- GitHub Actions (레포가 이미 GitHub. self-host 러너 없음, GitHub-hosted ubuntu-latest). 대안(CircleCI 등) 도입 부담 큼.

### 에이전트 자동 정리 시점

| 후보 | 평가 |
|---|---|
| **Claude Code PostToolUse hook** | Edit/Write 직후 변경 파일만 정리. CI 왕복 줄임. 실패해도 차단하지 않게 best-effort. ⭕ |
| pre-commit 훅 (git) | 일반 git hook은 에이전트 컨텍스트와 무관하게 발화. 설정 동기화 부담. |
| CI에서만 자동 수정 후 푸시 | PR 권한 확장 필요, 보안 표면 증가. 단일 운영자엔 과함. |

### CI 트리거 범위

| 후보 | 평가 |
|---|---|
| **path-filter** (`aggregation/**`, `pyproject.toml`, `.github/workflows/ci.yml`) | docs/ADR 변경에서 CI를 돌리지 않아 GitHub Actions 분 절약. ⭕ |
| 모든 PR에서 실행 | 단순하지만 docs-only PR에서도 ruff/pytest 돌아 비용 낭비 |
| 토픽별 별도 워크플로 | 현재 토픽이 aggregation 하나. raw 도입 시 분할 고려 |

## Decision

### 도구
- **Lint·Format**: `ruff` (단일 바이너리, 단일 설정 파일)
- **Test**: `pytest` (기존 유지)
- **CI 플랫폼**: GitHub Actions
- **에이전트 hook**: Claude Code PostToolUse hook (`.claude/settings.json` + `.claude/hooks/ruff-on-edit.sh`)

### ruff 설정 (`pyproject.toml`)
- `target-version = "py313"` (Lambda runtime 일치)
- `line-length = 100` (handler.py 가독성에 맞춘 절충)
- Lint 규칙 셋: `E, F, I, UP, B, SIM, RUF`
  - `E/F`: pycodestyle errors + pyflakes (기본)
  - `I`: import 정렬 (isort 대체)
  - `UP`: pyupgrade (Python 3.13 문법 권장)
  - `B`: bugbear (실수성 버그 패턴)
  - `SIM`: 단순화 권장
  - `RUF`: ruff 자체 규칙
- `ignore`: `E501`(line length는 formatter가 처리), `B008`(boto3 클라이언트 패턴), `SIM117`(테스트 가독성)
- `per-file-ignores`: `aggregation/tests/**` → `B017` (pytest.raises 광범위 허용)
- `format.quote-style = "double"`

### CI 워크플로 (`.github/workflows/ci.yml`)
- 트리거: PR + main push, 단 path-filter (`aggregation/**`, `pyproject.toml`, `.github/workflows/ci.yml`)
- 잡 1 — `python`:
  - `ruff check .`
  - `ruff format --check .`
  - `pytest`
- 잡 2 — `terraform`:
  - `terraform fmt -check -recursive`
  - `terraform init -backend=false` (state 접근 없음)
  - `terraform validate`
- 권한: `contents: read` (최소)
- 동시성: `concurrency` 그룹으로 같은 ref의 이전 실행은 cancel

### Claude 에이전트 hook
- 매처: `Edit|Write`
- 동작: `tool_input.file_path`가 `*/aggregation/*.py`일 때만
  - `ruff check --fix --quiet "$file"`
  - `ruff format --quiet "$file"`
- **항상 exit 0**: ruff 미설치·실패 시에도 차단 없음 (best-effort)
- PR 작성자가 최종 책임 (AGENTS.md §7 자체 변경 없음)

### `terraform plan`은 CI에 넣지 않는다
AGENTS.md §7과의 정합성 유지. AWS credentials를 GitHub Actions에 주입하지 않는다(보안 표면 최소화). plan은 로컬 → PR 본문 첨부 운영 그대로.

## Consequences

### Positive
- AGENTS.md §3의 TBD 해소. 컨벤션 표에 도구·위치 명시
- 머지 게이트 자동화 → 사람 리뷰가 로직·설계에 집중 가능
- 에이전트 자동 정리로 PR-CI 왕복 감소
- ruff 단일 도구 — 신규 기여자 onboarding 명령이 `pip install ruff` 한 줄

### Negative / Risks
- GitHub Actions 분 추가 사용. path-filter로 docs-only PR은 면제. AWS Budgets $5와는 무관 (GitHub 측 비용)
- ruff 규칙 변경 시 대량 자동 reformat 발생 가능 → 별도 `style:` 커밋으로 분리하기 (AGENTS.md §2의 "코드가 ADR과 다르면 버그" 원칙은 ruff 설정 변경 자체를 본 ADR 갱신 트리거로 둠)
- 로컬 Python 버전과 CI(`3.13`) 불일치 시 false 통과 가능 — README/AGENTS.md에 명시. 본 PR 작성자도 venv 3.9로 통과 확인 후 CI 통과 의존

### Re-evaluation Triggers
- 기여자 수 증가 → pre-commit 프레임워크 ROI 재평가
- handler.py 규모 증가 (~500 LOC↑) → mypy/타입체크 도입 재평가
- raw 토픽 도입 → 토픽별 별도 워크플로 분할 검토
- `terraform plan`이 사람 리뷰에서 자주 누락된다면 OIDC + GitHub Actions 통합 검토 (보안 표면 ↑ 트레이드오프)
- 에이전트 hook이 실제로 PR-CI 왕복을 줄이지 못한다면(데이터로 확인) 제거 또는 범위 조정

## References
- AGENTS.md §3 (컨벤션 표), §7 (검증 흐름)
- ADR-0001 — 토픽 분리·단일 운영자 가정 (path-filter 결정 근거)
- `docs/conventions/commit-convention.md` — type `ci`/`build`/`style` 정의
- ruff 공식 문서: <https://docs.astral.sh/ruff/>
