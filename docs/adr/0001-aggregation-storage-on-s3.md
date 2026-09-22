# ADR-0001: Aggregation Storage on S3

## Status
Accepted (2026-05-26)

> 2026-05-25: Proposed
> 2026-05-26: Accepted — 본 ADR이 정의한 아키텍처대로 aggregation 토픽 구현·배포가 완료되어 사실상 채택 상태. ADR-0002 작성과 함께 명시적으로 전환.
> 2026-05-29: Producer 책임 위치를 ADR-0003에서 본 레포 내부로 명시. 본 ADR의 architecture 결정 자체는 불변.

## Context and Problem Statement

Team-Neki-Platform는 네키 앱 도메인의 **일간 집계 데이터**(GA4 일간 리포트 등)를 수신·저장하는 책임을 가진다. 현재는 GitHub Actions cron이 매일 KST 10시에 GA4 데이터를 조회해 Discord로만 전송 중이며, 이 데이터를 영구 저장 가능한 형태로 보관할 필요가 발생했다.

본 ADR은 **일간 집계 데이터를 어떤 저장소에, 어떤 구조로, 어떤 파이프라인으로 보관할지** 결정한다.

## Goals
- 최소 의존성/최소 운영 부담
- 비용 최소화 (월 펜니 단위)
- 외부 소비자(분석 모듈/다른 레포)가 안정적으로 접근할 수 있는 contract 제공
- 추후 원본 로그(raw) 도입 시 자연스러운 확장성

## Non-Goals
- 분석/조회/시각화 (별도 모듈·레포 책임)
- 실시간 처리
- 다환경 운영 (dev/stage)
- 다계정 격리

## Decision Drivers
- 비용 (스토리지, 컴퓨팅, 운영)
- 단순성 (컴포넌트 수, 셋업 복잡도)
- 확장성 (raw 도입 시 마이그레이션 비용)
- AWS 기본 서비스 활용
- 분석 도구 호환성 (추후 Athena 등 도입 시)

## Considered Options

### 저장소

#### 평가 기준
- **비용 모델**: 스토리지/요청/유휴 비용 합산
- **접근 패턴 적합도**: 일 1회 PUT + 향후 비정기 ad-hoc 조회
- **운영 부담**: 유지보수, 백업, 패치
- **AWS 통합도**: Lambda 연동 용이성, IAM, 분석 도구 호환
- **확장성**: raw 로그 도입 시 호환성

#### 후보 비교

| 후보 | 스토리지 비용 | 유휴 비용 | 운영 부담 | Lambda 통합 | 분석 도구 호환 |
|---|---|---|---|---|---|
| **S3 ★ 선택** | $0.023/GB-월 | 0 | 거의 0 | 매우 우수 | Athena 네이티브 |
| DynamoDB | $0.25/GB-월 (10배) | 0 (On-Demand) | 낮음 | 매우 우수 | 제한적 (Export 필요) |
| MySQL (RDS) | 인스턴스 ~$15+/월 | 큼 | 중 (백업/패치) | 보통 | 외부 ETL 필요 |
| PostgreSQL (RDS) | 인스턴스 ~$15+/월 | 큼 | 중 | 보통 | 외부 ETL 필요 |
| MongoDB | 인스턴스 비용 | 큼 | 중 | 보통 | 외부 ETL 필요 |

#### 비채택 근거

**RDB (MySQL/PostgreSQL)**
- 가장 작은 인스턴스도 월 $15+ 유휴 비용 발생
- 일 1회 쓰기·비정기 읽기 패턴에 상시 인스턴스는 명백한 오버스펙
- 운영 부담(백업/패치/모니터링)이 데이터 가치 대비 과함
- PostgreSQL의 분석 함수 강점은 강력하지만, 본 프로젝트는 분석을 명시적 non-goal로 분리했음

**MongoDB**
- RDB와 동일한 인스턴스 유휴 비용 문제
- 스키마 유연성 이점이 작용하기엔 본 데이터가 이미 정형화됨
- 추가 비용을 정당화할 강점 없음

**DynamoDB**
- 인스턴스 유휴 비용은 없으나 **스토리지 단가가 S3의 10배**
- 일 1 객체 패턴에 키-값 조회 강점이 발동하지 않음
- 분석 도구 호환성이 약함 → Export to S3 + Athena 우회 필요 시 데이터가 결국 S3에 두 번 존재
- 본 데이터가 자연스럽게 "일 단위 객체 1건" = 파일 모델인데 키-값 모델로 강제할 이유 없음

#### S3 채택 근거

1. **트래픽 패턴 적합도**: 일 1회 PUT + 비정기 GET이 S3 객체 모델과 직결
2. **비용 절대치**: 다른 모든 옵션 대비 1~2 자릿수 저렴 (월 펜니 단위)
3. **운영 부담 0**: 인스턴스 개념 없음 → 패치/백업/모니터링 불필요
4. **분석 도구 호환**: 향후 분석 모듈이 별도 ETL 없이 Athena/Spark/Pandas로 직접 접근 가능 (S3 객체가 곧 contract)
5. **확장성**: Hive-style 파티션으로 raw 도입 시 동일 컨벤션 유지
6. **AWS 네이티브**: Lambda boto3 `put_object` 한 줄로 통합

#### 결정에 영향을 준 핵심 인사이트
- "분석은 다른 모듈/레포 책임"이라는 스코프 결정이 RDB의 강점(SQL 쿼리)을 본 프로젝트에서 무력화시켰음
- "aggregation과 raw 완전 독립" + "버킷은 공유"의 합의가 S3의 prefix 분리 모델과 부합

---

### 수신 패턴

- **API Gateway → Lambda → S3 직접 쓰기 ★ 선택**
  일 1회 호출에 적합. 컴포넌트 최소, Lambda에서 검증 로직 직접 제어. 멱등성은 S3 키 고정(`year=/month=/day=/...`) 덮어쓰기로 자연 확보.

- API GW → Lambda → DynamoDB → 배치 → S3
  비동기 응답·중복 방지가 강점. 일 1회·작은 페이로드에는 컴포넌트가 2배가 되어 명백한 오버스펙. DynamoDB 스토리지 비용도 추가.

- API GW → Kinesis Firehose → S3
  스트리밍 버퍼링/Parquet 자동 변환이 강점. 초당 수십~수백 건 트래픽이 있어야 가치. 일 1회 케이스엔 Firehose ingestion 비용($0.029/GB)만 추가됨.

---

### 인증

- **Public + Shared Secret URL ★ 선택**
  Discord Webhook과 동일한 보안 모델. URL을 GitHub Actions Secret으로 관리. 유지할 시크릿 1개, 셋업 0. 안전장치(throttling / 입력검증 / Budgets / concurrency)로 위험을 보완.

- API Key (헤더 기반)
  키 회전 운영 부담. URL과 키 두 시크릿 관리. 본 케이스의 위험도 대비 추가 복잡도가 정당화되지 않음.

- IAM (GitHub OIDC)
  유출될 시크릿 자체가 없는 최상위 보안. OIDC Provider + IAM Role + Trust Policy 셋업 필요. 데이터 가치/공격 동기가 낮은 본 케이스엔 과보호. 데이터 민감도 상향이 재검토 트리거.

---

### 파일 포맷
- **JSON ★ 선택**: 중첩 구조 자연스러움. 데이터가 작아 Parquet 압축 이점 없음.
- Parquet: 컬럼/압축 이점은 raw 도입(대용량) 시점에 가치. 현재 non-goal.

## Decision

### 아키텍처

```
GitHub Actions (cron, 10:00 KST)
   ↓ HTTPS POST (Shared Secret URL)
API Gateway (public)
   ↓
Lambda (검증·정규화)
   ↓ PUT
S3 (영구 저장)
```

### 저장 구조
- **S3 버킷**: `team-neki-log-production`
- **객체 키**: `aggregation/year=YYYY/month=MM/day=DD/ga4-daily-report.json`
- **포맷**: UTF-8 JSON
- **파티션**: Hive-style (`key=value/`), 제로 패딩
- **날짜 기준**: KST 보고 대상 일자
- **Versioning**: OFF (데이터 유실 허용; 복구는 GitHub Action 재실행)
- **Lifecycle**: 없음 (Standard 영구 보관)
- **Public Access Block**: 활성화 (S3 기본값)
- **암호화**: SSE-S3 (S3 기본값, 2023+ 자동)

### 리소스 네이밍

| 리소스 | 이름 |
|---|---|
| S3 버킷 | `team-neki-log-production` |
| Lambda | `team-neki-log-aggregation-production-ingest` |
| API Gateway | `team-neki-log-aggregation-production` |
| IAM Role | `team-neki-log-aggregation-production-lambda-role` |
| CloudWatch Log Group | `/aws/lambda/team-neki-log-aggregation-production-ingest` |

> 버킷은 공유 자원, 다른 리소스는 aggregation 스코프 명시.
> raw 도입 시 별도 인프라(`team-neki-log-raw-production-*`) + 같은 버킷의 `raw/` prefix 사용.

### 페이로드 Contract
- 정규화된 JSON
- 최상위에 `schema_version` 필드 포함 (예: `"1.0"`)
- 상세 스키마는 별도 문서 (`docs/payload-schema.md`, 추후 작성)

### 인증·안전장치
- API Gateway는 인증 없는 public endpoint
- URL을 GitHub Actions Secret으로 보관 (shared secret 역할)
- 안전장치:
  - **API Gateway Throttling**: 10 req/sec, 일 1000건 제한
  - **Lambda 입력 검증**: 스키마, 날짜 범위(최근 7일 이내), 필수 필드
  - **AWS Budgets 알림**: 월 $5 한도, 초과 시 이메일
  - **Lambda Reserved Concurrency**: 2

### Timezone
- 본 시스템은 GA4 reporting timezone이 **KST (GMT+09:00)** 임을 전제로 한다 (Producer가 호출하는 GA4 property `524989384`의 reporting timezone 설정값)
- S3 경로 `day=` 값과 JSON `report_date` 모두 KST 보고 대상 일자
- GitHub Actions cron `0 1 * * *` (UTC 01:00 = KST 10:00)
- **주의**: cron을 UTC 00:00–09:00 영역으로 옮기면 UTC 어제와 KST 어제가 달라짐. 변경 시 Python `yesterday` 계산을 KST 기준으로 명시화 필요

## Consequences

### Positive
- 월 비용 펜니 단위 (예상: < $1/월)
- 단일 AWS 계정, prod 단일 환경 → 운영 부담 최소
- 데이터가 S3에 안정적으로 누적
- raw 도입 시 동일 버킷 prefix 추가만으로 확장
- 데이터 자체가 외부 소비자에 대한 명시적 contract

### Negative / Risks
- API URL 노출 시 데이터 주입·덮어쓰기 위험. Versioning OFF이므로 복구는 GitHub Action 재실행에 의존
- dev 환경 부재 → prod 변경 시 `workflow_dispatch` + 옛 날짜로 우회 검증 필요
- 분석 기능 부재 (의도된 non-goal, 별도 모듈/레포 책임)

### Re-evaluation Triggers
- 데이터에 **PII/매출 등 민감 정보** 포함 시 → 인증 강화(API Key 또는 OIDC)
- **URL 노출 사고** 발생 시 → 인증 추가 + URL 회전
- **호출 빈도가 분당 수십 건 이상** 증가 시 → 수신 패턴 재검토
- **보관 데이터가 100GB 초과** 시 → Lifecycle 도입 검토
- **raw 도입** 시 → raw용 인프라/경로를 별도 ADR로 정의
- **변경 빈도 증가**로 prod 직접 검증 위험이 커질 시 → dev 환경 도입

## References
- 작성 컨텍스트: 2026-05-25 의사결정 ping-pong 대화
- 관련 자산:
  - `scripts/ga_daily_report.py` (GA4 호출 스크립트)
  - `.github/workflows/daily-ga-report.yml` (GitHub Actions 워크플로)
- 추후 작성 예정: `docs/payload-schema.md`
