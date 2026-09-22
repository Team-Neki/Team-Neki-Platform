# Roadmap

Team-Neki-Platform에서 진행해야 할 작업을 명시적으로 기록한다. 새 작업이 생기거나 상태가 바뀌면 본 문서를 갱신한다.

## Status

| 표기 | 의미 |
|---|---|
| `[ ]` | TODO |
| `[~]` | 진행 중 |
| `[x]` | 완료 |
| `[-]` | 보류 / 차단됨 |

## 완료된 작업 (요약)

- [x] ADR-0001 작성 — S3 저장소 선택 의사결정
- [x] HLD 작성 — aggregation 토픽 시스템 구조
- [x] LLD 작성 — API contract / 스키마 / IaC 명세
- [x] aggregation 구현 — Lambda handler, JSON Schema, 테스트, Terraform IaC
- [x] PR #1 OPEN ([링크](https://github.com/Team-Neki/Team-Neki-Platform/pull/1))

---

## Phase 1. PR #1 검토 및 머지

리뷰어가 확인할 항목.

- [ ] ADR/HLD/LLD 의사결정 검토 (mermaid 다이어그램 렌더링 포함)
- [ ] JSON Schema가 실제 GA4 페이로드 매핑에 적합한지 확인
- [ ] Lambda IAM 최소 권한 검증 (`s3:PutObject` on `aggregation/*` only)
- [ ] Terraform 리소스 누락/잉여 검토
- [ ] PR #1 머지 (Squash 또는 Rebase merge 권장)

**Exit criteria**: PR #1 머지, main에 docs + aggregation 구현 반영.

---

## Phase 2. 첫 배포 (Terraform)

수동 셋업 + 인프라 프로비저닝.

### 사전 준비
- [ ] AWS 자격증명 준비 (etc/ 안에서 작업 → koosco 계정)
- [ ] GA4 property `524989384`의 reporting timezone이 **KST**인지 콘솔에서 확인
- [ ] `aggregation/infra/terraform.tfvars` 생성 후 `alert_email` 본인 이메일로 설정
- [ ] 로컬에 Terraform 1.5+ 설치 확인

### 배포 실행
- [ ] `cd aggregation/infra && terraform init`
- [ ] `terraform plan` 결과 검토
- [ ] `terraform apply`
- [ ] 출력 `api_endpoint` 값 기록
- [ ] AWS Budgets 알림 이메일의 SNS subscription **confirm 링크 클릭**

**Exit criteria**: S3 버킷·Lambda·API Gateway·IAM·CloudWatch Log Group·AWS Budgets가 모두 생성되어 API endpoint가 응답 가능한 상태.

---

## Phase 3. Producer 측 통합

GA4 일간 리포트 GitHub Actions에서 본 endpoint 호출 추가. (Producer는 별도 레포에 위치)

- [ ] Producer 레포에 `NEKI_LOG_INGEST_URL` Secret 등록 (Phase 2의 `api_endpoint` 값)
- [ ] `ga_daily_report.py` 수정
  - GA4 응답 → 정규화 JSON 페이로드 변환 함수 추가
  - 필드: `schema_version`, `report_date` (KST), `report_type=ga4-daily-report`, `generated_at` (UTC ISO 8601), `source.property_id`, `events`, `dimensions`
  - Discord 알림과 **병렬로** API endpoint에 POST
  - 4xx 응답 시 재시도 금지 (페이로드 결함)
  - 5xx 응답 시 워크플로 실패 처리 (다음 cron이 재시도하거나 `workflow_dispatch`로 수동 재실행)
- [ ] PR로 변경 머지

**Exit criteria**: GitHub Actions 다음 cron 실행에서 S3에 객체 1개 생성됨.

---

## Phase 4. 운영 검증 (배포 ~ 7일)

- [ ] 7일 연속 정상 객체 적재 확인 (S3 콘솔)
- [ ] CloudWatch Logs에서 `validation_failed` / `s3_put_failed` 등 이상 로그 없음 확인
- [ ] AWS Cost Explorer로 월 비용이 예상($1 미만) 범위 내인지 확인
- [ ] AWS Budgets 80% 알림이 임계 미만이라 안 오는 것 확인

**Exit criteria**: 안정 운영 상태 확인. Phase 5로 진행하거나 운영 모드로 전환.

---

## Phase 5. Terraform state S3 마이그레이션 (선택) — 2026-06-09 완료

초기 배포는 local state 였고 S3 로 옮겼다. 지금 `aggregation/infra` 의 정본 state 는 S3 에 있다.

- [x] `aggregation/infra/main.tf`의 `backend "s3"` 블록 주석 해제
- [x] `terraform init -migrate-state` 실행
- [x] state가 `s3://team-neki-log-production/terraform/state/aggregation.tfstate`에 존재 확인
- [x] 로컬 `terraform.tfstate*` 백업 후 삭제

마이그레이션 이전 상태(serial 15)는 `~/Downloads/aws-cleanup-backup-2026-09-23/aggregation-pre-migration.tfstate.bak`
으로 옮겼고, 비어 있던 `terraform.tfstate`(0 바이트)는 지웠다. 이제 저장소에도 워크스페이스
어디에도 로컬 state 파일이 없다.

**로컬 state 파일을 남겨두지 않는다.** 백엔드가 S3 이면 Terraform 이 로컬 파일을 보지
않으므로 있어도 동작에 영향은 없지만, 백엔드 설정이 없는 저장소에서는 그 파일이 정본이
된다. 실제로 Server 저장소가 그 상태였고 `destroy` 한 번이면 운영 버킷이 사라지는
구조였다 (BACKEND-136).

**Exit criteria**: state가 S3에 있고 다른 환경에서도 `terraform init`으로 state 공유 가능. 충족됨.

---

## Future / Non-Goal (재검토 트리거 발생 시 진행)

현재 의도적으로 범위 밖에 둔 항목. 트리거 조건 발생 시 별도 ADR/HLD/LLD로 진행한다.

| 항목 | 재검토 트리거 |
|---|---|
| 원본 로그(raw) 수집 | 분석 요구사항이 집계치만으로 부족 |
| 분석/조회 모듈 | 별도 레포 또는 모듈로 신규 진행 |
| dev 환경 도입 | 변경 빈도 증가, prod 직접 검증 위험 |
| 인증 강화 (API Key/OIDC) | PII 포함, URL 노출 사고, 또는 호출 빈도 분당 수십 건 이상 |
| CloudWatch 알람 / 대시보드 | 운영 가시성 필요성 증가 |
| Lambda 코드 배포 파이프라인 분리 | 코드 변경 빈도가 인프라 변경 빈도보다 훨씬 잦아질 때 |
| S3 Lifecycle 도입 | 보관 데이터 100GB 초과 |

---

## References
- [ADR-0001: Aggregation Storage on S3](../adr/0001-aggregation-storage-on-s3.md)
- [HLD: Aggregation](../aggregation/hld.md)
- [LLD: Aggregation](../aggregation/lld.md)
- [aggregation/README.md](../../aggregation/README.md) — 셋업 절차 상세
