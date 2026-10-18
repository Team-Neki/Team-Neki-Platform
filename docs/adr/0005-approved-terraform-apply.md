# ADR-0005: 수동 실행과 사용자 승인에 따른 Terraform 적용

## Status
Accepted (2026-10-19), 사용자 요청. ADR-0002의 Actions plan 금지는 수동 배포 workflow에 한해 대체한다. PR CI는 기존대로 유지한다.

## Context and Problem Statement
로컬에서만 가능했던 apply를 GitHub Actions에서 실행하고, 운영자가 plan 이후 명시 승인해야 한다.

## Decision
- `workflow_dispatch`로 main의 모듈 하나를 선택한다. PR/push 자동 배포는 하지 않는다.
- plan → GitHub Environment `terraform-apply` 승인 → 저장된 plan apply로 분리한다.
- required reviewer는 `koosco` 한 명, 관리자 우회 금지, 배포 브랜치는 main만 허용한다. 단일 운영자가 직접 실행 후 승인할 수 있도록 self-review는 허용한다.
- 기존 repository AWS Secrets를 재사용한다. IAM 확장과 신규 AWS 리소스는 없다. OIDC/역할 분리는 별도 결정으로 남긴다.
- 전역 concurrency를 두고 실행 중 취소를 막는다. 로컬 apply와의 동시 실행은 운영자가 피한다.
- delete/교체가 포함된 plan은 차단한다. 실제 삭제가 필요한 변경은 별도 검토한다.
- 저장 plan에 포함되는 비밀값은 `TF_PLAN_KEY`로 암호화하여 1일 artifact로 보관한다. 공개 summary에는 리소스 주소/작업과 commit만 출력하고 원시 plan/apply 로그는 업로드하지 않는다.
- apply 직전 main SHA를 확인하며 변경됐다면 새 실행/승인을 요구한다. plan과 apply는 같은 Terraform 버전과 lockfile을 사용한다.

## Consequences
- 사용자는 Actions summary와 해당 commit의 코드 변경을 확인한 뒤 Review deployments에서 승인/거절한다.
- 변경 없음은 승인을 요청하지 않는다. artifact 만료/실패 시 새 실행으로 plan부터 진행한다.
- AWS 자격증명은 기존과 같은 repository secret이므로 다른 workflow에서도 사용 가능하다. Environment 승인은 이 workflow의 apply job을 보호하며 계정 전체의 IAM 경계는 아니다.
- 원시 실패 로그는 공개하지 않으므로 장애 원인은 로컬 plan 및 AWS/state 확인이 필요하다.
- GitHub-hosted runner 분 사용 외 AWS 신규 고정 비용은 없다.

## References
- [GitHub Environment 승인](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)
- [ADR-0002](0002-lint-and-ci-pipeline.md)
