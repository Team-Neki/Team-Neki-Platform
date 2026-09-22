# Commit Convention

Team-Neki-Platform의 git commit 메시지 규칙. 신규/외부 기여자 모두 이 문서 한 장으로 작성 가능해야 한다.

## 1. 기본 포맷

[Conventional Commits 1.0](https://www.conventionalcommits.org/ko/v1.0.0/) 기반.

```
<type>(<scope>): <제목 (한국어)>

<본문 (한국어, 선택)>

<trailer (선택)>
```

- **type**: 영문 소문자 (스펙 고정)
- **scope**: 영문 소문자 (토픽명, 아래 §3)
- **제목**: 한국어, 50자 이내 권장, 마침표 없음, 명령형/요약형
- **본문**: 한국어, 한 줄 72자 wrap 권장. **무엇**보다 **왜**를 적는다
- **본문/trailer는 빈 줄로 구분**

### 예시

```
feat(aggregation): report_date 범위 검증 추가

유출된 URL을 통한 과거 데이터 주입을 차단하기 위해
7일 이전 report_date를 거부한다. 미래 일자도 +1일까지만 허용.

Refs: ADR-0001
```

```
fix(aggregation): S3 객체 키의 month/day zero-padding 누락 수정

YYYY-M-D 형태로 저장되어 Hive 파티션 스캔이 깨지던 문제 해결.

Refs: LLD §4.1
```

## 2. Type 목록

| type | 사용 시점 |
|---|---|
| `feat` | 사용자/소비자가 인지하는 새 기능. 새 endpoint, 새 검증 규칙, 새 스키마 필드 등 |
| `fix` | 버그 수정 |
| `docs` | 문서만 변경 (ADR/HLD/LLD/README/주석) |
| `refactor` | 동작 변화 없는 코드 구조 변경 |
| `perf` | 성능 개선 (동작 동일) |
| `test` | 테스트 추가/수정 |
| `build` | 빌드/패키징/의존성 변경 (`requirements.txt`, `pyproject.toml`) |
| `ci` | GitHub Actions, 빌드 파이프라인 변경 |
| `chore` | 위 어디에도 속하지 않는 잡무 (`.gitignore`, 도구 설정 등) |
| `style` | 포맷팅/세미콜론/공백 등 의미 없는 변경 (ruff/black) |
| `revert` | 이전 커밋 되돌리기 (`revert: <원본 제목>`) |

> 애매할 땐 **소비자 관점**으로 판단: API 응답·페이로드·저장 경로가 바뀌면 `feat`/`fix`, 내부만 바뀌면 `refactor`/`chore`.

## 3. Scope (토픽 기반)

ADR/HLD에서 정의한 **토픽** 단위로 적는다. 디렉토리 구조와 1:1이 아닐 수 있다 (디렉토리는 바뀌어도 토픽은 안정적).

| scope | 의미 |
|---|---|
| `aggregation` | 일간 집계 수신/저장 토픽 (현재 유일한 토픽) |
| `raw` | 원본 로그 수집 토픽 (향후 도입) |
| `infra` | 토픽에 종속되지 않는 공통 인프라 (계정, terraform backend 등) |
| `docs` | ADR/HLD/LLD/README 등 문서 |
| `ci` | GitHub Actions, repo automation |
| `repo` | 레포 메타 (gitignore, convention, templates 등) |

토픽이 여러 개에 걸치면:
- 명확한 주된 scope 1개 선택 후 본문에 부수 영향 기술
- 정말 동등하면 `chore: ...` (scope 생략)

신규 scope 도입은 ADR 또는 토픽 LLD 작성과 함께 이 표를 업데이트한다.

## 4. Breaking Changes

소비자 contract를 깨는 변경 — 페이로드 스키마, S3 객체 키 구조, API 경로/응답 envelope, IAM 권한 축소 등.

표기 규칙:
1. 제목의 type/scope 뒤에 `!` 표기
2. 본문에 `BREAKING CHANGE:` 단락으로 영향 + 마이그레이션 기술

```
feat(aggregation)!: payload schema_version을 2.0으로 승격

events 필드 구조를 events[].name + events[].count 배열로 변경.

BREAKING CHANGE:
- 기존 1.x 페이로드는 UNSUPPORTED_SCHEMA_VERSION으로 거부됨
- Producer는 신 스키마로 마이그레이션 필요
- 마이그레이션 가이드: docs/migrations/0002-schema-v2.md

Refs: ADR-0002
```

## 5. Trailer

본문 다음 빈 줄 후, `Key: value` 형식. 여러 줄 가능.

### 5.1 `Refs:` (필수)

의사결정/설계 문서 또는 이슈 링크. 이 레포는 ADR/HLD/LLD를 기준 문서로 운영하므로 **거의 모든 커밋이 어떤 문서 결정에 근거**한다.

```
Refs: ADR-0001
Refs: HLD §4.3
Refs: LLD §6.1, ADR-0001
Refs: #42                  # 이슈 번호
Refs: ADR-0001#재검토트리거 # 섹션 앵커
```

생략 가능한 예외:
- `style:`, 오타 수정 등 의사결정 무관 변경
- 단 PR 본문에는 그래도 맥락 명시 권장

### 5.2 `Co-Authored-By:` (허용)

페어/AI 협업 시 명시 가능. 형식은 git 표준:

```
Co-Authored-By: 홍길동 <gildong@musinsa.com>
Co-Authored-By: Claude <noreply@anthropic.com>
```

- 자동 삽입 강제하지 않음. 의미 있는 협업이었을 때만 적는다
- AI 단독 생성을 인간 작업으로 위장하지 않는다

### 5.3 그 외 trailer

- `Reviewed-by:`, `Tested-by:`: 선택. PR 리뷰 흔적이 GitHub에 남으므로 보통 생략

## 6. Squash & Merge 시 메시지

PR을 squash merge 할 때 GitHub가 제안하는 기본 메시지는 보통 부적합하다 (`* fix typo` 누적).

**원칙**: squash 결과 커밋이 main에 남을 단일 사실이다. 위 컨벤션을 그대로 적용해 손으로 다듬는다.

- 제목: PR 제목 그대로 또는 더 정확하게 재작성
- 본문: PR 본문의 핵심 (Why / 영향) 옮기기
- `Refs:`, `Co-Authored-By:` trailer 유지

## 7. 자주 하는 실수

- 한 커밋에 여러 토픽 섞기 → 분리
- 제목에 "수정", "변경" 같은 무정보 단어만 쓰기 → 무엇이/왜 바뀌었는지 명시
- 본문 없이 큰 변경 commit → 본문에 의도/영향 1~2문장 필수
- ADR 번호 없이 결정 변경 → 먼저 ADR 작성 후 그 번호를 `Refs:`에 인용
- `chore:` 남용 → 가능한 정확한 type 선택
