<!--
PR 제목은 commit convention과 동일하게 작성:
  type(scope): 한국어 제목
  예) feat(aggregation): report_date 범위 검증 추가
  예) fix(infra)!: S3 bucket 이름 변경 (BREAKING)

자세한 규칙: docs/spec/commit-convention.md
-->

## Summary

<!-- 이 PR이 무엇을 바꾸는지, 왜 바꾸는지 1~3문장. 배경/문제 → 해결 방향. -->

## Changes

<!-- 주요 변경 대상을 컴포넌트/파일 단위 불릿으로. 사소한 변경은 생략 가능. -->

- 

## References

<!--
의사결정/설계 문서 링크 필수. 없으면 사유 명시.
형식 예시:
- ADR-0001 §재검토트리거
- HLD §4.3
- LLD §6.1
- Issue #42
-->

- 

## How to verify

<!--
리뷰어가 직접 돌려볼 수 있도록.
- 테스트 명령
- 수동 검증 시나리오 (입력/기대 결과)
- terraform plan 결과 요약 (infra PR일 때)
-->

```
# 예) pytest aggregation/tests -q
# 예) curl -X POST $API_URL -d @fixtures/valid_payload.json
```

## Breaking changes

<!--
소비자 contract(payload schema / S3 키 / API 경로/응답 envelope / IAM)에 영향 있나?
없다면 "없음" 한 단어. 있다면 영향 + 마이그레이션 절차 명시.
-->

없음

## Operational impact

<!--
- 비용: AWS 리소스 추가/제거, 예상 월 비용 변화
- 보안: IAM 변경, public 노출 변화
- 운영: 수동 단계 추가 (Secret 등록, 알림 이메일 confirm 등)
- 모니터링/알람 변경
영향이 없다면 "없음".
-->

없음

## Screenshots / Logs

<!-- 필요 시 실행 로그, 콘솔 캡처, 응답 샘플. 없으면 섹션 자체 삭제 가능. -->

## Checklist

- [ ] 관련 ADR/HLD/LLD 또는 Issue를 **References**에 링크했다 (또는 사유 명시)
- [ ] Breaking change 여부를 **Breaking changes** 섹션에 명시했다 (`!` 표기 일치)
- [ ] **How to verify**에 적힌 검증 절차를 직접 수행했다 (테스트 / 로컬 / `terraform plan`)
- [ ] Infra 변경 시 `terraform plan` 결과를 PR 본문 또는 코멘트에 첨부했다
- [ ] 코드/PR 본문/커밋 어디에도 API URL, AWS key, Secret 값이 노출되지 않았다
- [ ] AWS 비용 영향(신규 리소스 / 호출량 증가 / 보관량)을 검토했고 예상 범위 내다
