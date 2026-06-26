# Worklog

> 누적형 작업 로그. 새 파일을 만들지 않고 이 파일에만 append.
> 의미 있는 작업 단위만 기록. 단순 조회/포맷 변경/사소한 확인은 한 줄 또는 생략.
> 형식: 각 엔트리는 `## YYYY-MM-DD — 제목` 헤더 + 아래 8필드.

---

## 2026-05-24 — 최상위 README: paste-and-run + .env.example 신설

- **상태**: DONE
- **한 일**:
  - 최상위 [README.md](../README.md) 의 빠른 시작을 **4개 자산(packages/blueprints/forms) 전체 업로드** 한 블록으로 통합. 토큰 발급 → `/vco/api/packages` → `/blueprint/api/blueprints` + release → `/form-service/api/forms` 순.
  - [.env.example](../.env.example) 신설 — `VCFA_URL/USER/PASSWORD/DOMAIN/PROJECT_NAME` 템플릿. README에서 `cp .env.example .env && vi .env && source .env` 흐름으로 안내.
  - `.gitignore`는 이미 `.env` 제외 + `!.env.example` 예외라 추가 변경 없음.
- **수정한 파일**: [README.md](../README.md), [.env.example](../.env.example)
- **검증**: `git check-ignore` 로 `.env` 제외 / `.env.example` 커밋 가능 확인. 실 호출 미검증.
- **중복 방지 메모**: 자산 업로드 예시는 **최상위 README 한 곳에만**. 폴더별 README는 UI 위주 + 세부 endpoint 검증 노트만.

---

## 2026-05-24 — 자산별 REST 빠른 시작에 토큰 발급 인라인 (paste-and-run)

- **상태**: DONE
- **한 일**: blueprints/forms/packages 의 "REST API (curl) 로 업로드" 절을 자체 완결로 재구성. 환경값 + 토큰 발급(`/csp/gateway/am/api/login` → `/iaas/api/login`) + AUTH 배열까지 한 블록으로 박아, 위에서부터 그대로 paste하면 토큰 발급부터 업로드까지 즉시 실행. forms에는 PROJECT_ID 조회까지 0번 블록에 포함.
- **수정한 파일**: [blueprints/README.md](../blueprints/README.md), [forms/README.md](../forms/README.md), [packages/README.md](../packages/README.md)
- **검증**: 세 README 모두 "0) 환경값 + 토큰 발급 → 1) ... → 2) ..." 순서로 통일. deploy.md §6은 endpoint 검증 포인트(환경 캡처) 참조 용도로만 유지 — 중복은 토큰 블록뿐(의도된 중복, paste-and-run 원칙 우선). 실 환경 호출은 미검증.
- **남은 작업**: 환경 캡처값으로 endpoint·페이로드 키 확정.
- **중복 방지 메모**: 토큰 블록은 세 자산 README에서 동일 — endpoint나 인자가 환경에 따라 달라지면 세 곳 동시 갱신. 그 외 자산별 차이만 1)/2) 절에.
- **주의사항**: 시크릿은 항상 env, 토큰 echo 금지(길이만). `CURL_K=()` 가 운영 기본, `(-k)` 는 검증용 한정.

---

## 2026-05-24 — Terraform 영역 제거 + 자산별 "VCFA 업로드 REST" 정리

- **상태**: DONE
- **한 일**:
  - 사용자가 `terraform/` 폴더를 삭제 → 관련 자료 일괄 제거:
    - [.gitignore](../.gitignore) — TF 패턴 제거, 일반 시크릿 패턴만 유지
    - [README.md](../README.md) — terraform/ 행 제거, "scripts/ 자동화" 자리도 없앰 (사용자 의도 아님)
    - [docs/context.md](context.md) — terraform/ 행 + scripts/ 행 제거
    - [docs/architecture.md](architecture.md) — `terraform/` 트리 및 "Terraform 영역" 절 제거
    - [docs/runbooks/offline-setup.md](runbooks/offline-setup.md) — TF mirror 절 제거, vRO 패키지 무결성·이전 매체·시크릿·REST 포인터 위주로 재작성
  - 자산별 README에 **VCFA에 업로드하기 위한 REST/curl 절** 추가 (사용자 요청: "스크립트 만들지 말고 요청 방법을 README에 정리"):
    - [docs/runbooks/deploy.md §6](runbooks/deploy.md) — 공통 토큰 발급 절차(2단계: `/csp/gateway/am/api/login` → `/iaas/api/login`) + `VCFA_TOKEN` env로 노출 + 환경 캡처 검증 포인트
    - [blueprints/README.md](../blueprints/README.md) — `POST /blueprint/api/blueprints` 생성/업데이트, `POST /blueprint/api/blueprints/{id}/versions` 릴리스
    - [forms/README.md](../forms/README.md) — `/catalog/api/sources` → `/catalog/api/items` → `POST /form-service/api/forms` 패턴
    - [packages/README.md](../packages/README.md) — `POST /vco/api/packages` multipart (공통 인증 참조로 단순화)
    - [actions/README.md](../actions/README.md) — 액션 단위 API보다 패키지 단위 권장, [packages/README.md](../packages/README.md) 로 연결
  - 메모리 갱신: `project_vcfa_scope.md` (TF 제외), `feedback_vcfa_scope_includes_terraform.md` (OBSOLETE 표시 + 여전히 유효한 부분만 보존), `MEMORY.md` 라인 갱신.
- **픽스한 내용**:
  - 사용자가 폴더만 지웠을 때 흩어져 있던 TF 참조 제거 (`.gitignore` 6개 패턴, 5개 문서, 메모리 2개).
  - REST 절 중복 제거 — 공통 토큰 발급은 [deploy.md §6](runbooks/deploy.md) 한 곳에만, 각 자산은 거기를 참조.
- **수정한 파일**:
  - 갱신: [.gitignore](../.gitignore), [README.md](../README.md), [docs/context.md](context.md), [docs/architecture.md](architecture.md), [docs/runbooks/offline-setup.md](runbooks/offline-setup.md), [docs/runbooks/deploy.md](runbooks/deploy.md), [blueprints/README.md](../blueprints/README.md), [forms/README.md](../forms/README.md), [packages/README.md](../packages/README.md), [actions/README.md](../actions/README.md)
  - 메모리: `project_vcfa_scope.md`, `feedback_vcfa_scope_includes_terraform.md`, `MEMORY.md`
- **검증**:
  - `grep -rE "terraform|tfstate|tfvars|vmware/vcfa|providers\.tf"` 으로 잔존 TF 키워드 확인 → 본 worklog 엔트리(이력)만 남음.
  - REST endpoint 사실: vRO 패키지 `/vco/api/packages`는 vRO 8.x 공식 문서 패턴. VCFA 블루프린트 `/blueprint/api/blueprints`·폼 `/form-service/api/forms` 는 vRA 8.x 문서 기준이며 VCFA 9에서 보편적이지만 환경별 base URL prefix는 **"환경 캡처로 확정 필요"** 로 모든 README에 명시.
  - 토큰 2단계 (`/csp/gateway/am/api/login` → `/iaas/api/login`)도 vRA 8.x 문서 기준. 환경 다르면 DevTools 캡처로 교체 안내.
  - 전체 문서 상대 링크 자동 검사 → 0 broken (이전 turn 검사 통과 후 link 변경 없음).
  - 실 VCFA에서의 curl 호출 동작은 환경 부재로 **미검증**.
- **실패/미완성**:
  - VCFA 9 번들 환경의 정확한 base URL prefix·토큰 응답 키 미검증. 사용자가 한 번 캡처해 README 값을 교체 권장.
  - 자동화 스크립트 의도적으로 안 만듦 (사용자 요청 아님). 필요 시 별도 요청 시 추가.
- **남은 작업**:
  - 사용자 환경 캡처값으로 4개 README의 endpoint·페이로드 확정.
  - `roles_management`·`importing_resources` 같은 별도 자산 도입 여부는 사용자 결정 대기.
- **중복 방지 메모**:
  - **Terraform은 본 리포 범위에서 제외**. 다시 인프라 깔지 말 것.
  - REST 토큰 절차는 [deploy.md §6](runbooks/deploy.md) **한 곳에만**. 자산 README는 거기를 참조.
  - 각 자산 README의 "환경 검증 포인트"는 같은 패턴 — UI 한 번 + DevTools 캡처.
  - 스크립트(`scripts/`)는 사용자가 명시 요청할 때만.
- **주의사항**:
  - 토큰 자체·비밀번호는 로그에 절대 echo 금지(길이만 출력하는 패턴 유지).
  - `INSECURE=1` (curl -k) 은 검증 단계 한정, 운영 금지.
  - `archive/` 폴더 자산은 REST 업로드 시에도 사용 금지.

---

## 2026-05-24 — terraform/ state lock·이식성·remote backend 절 추가

- **상태**: DONE
- **한 일**: `terraform/README.md` (삭제됨) 에 "State 잠금 해제 · 다른 머신/CI에서 배포" 섹션 추가. 네 가지 항목:
  - A) **State lock stuck → `terraform force-unlock`** + 대기 옵션(`-lock-timeout`). 파일 직접 삭제·`-lock=false` 는 비권장으로 명시.
  - B) **Dependency lock (.terraform.lock.hcl) 의 플랫폼 호환성** → `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64` 로 multi-platform 해시 추가.
  - C) **`backend "local"` 한계 → remote backend 전환** (s3+DynamoDB, gcs, azurerm, pg, consul, Terraform Cloud 비교표) + `terraform init -migrate-state` 절차 + `data "terraform_remote_state"` backend 동일 교체.
  - D) **CI 권장 옵션**: `-input=false`, `-lock-timeout`, `-out=tfplan` plan/apply 분리.
- **픽스한 내용**: 그동안 quick start에 박혀 있던 `backend "local" {}` 의 다중 위치 한계를 명시적으로 표기. 사용자가 "다른 곳에서 배포할 때 lock 해제 필요" 라고 지적 → 정정.
- **수정한 파일**: `terraform/README.md` (삭제됨), [worklog.md](worklog.md)
- **검증**:
  - `terraform force-unlock`, `-lock-timeout`, `terraform providers lock -platform=`, `terraform init -migrate-state` 모두 표준 Terraform CLI 명령 (provider 비종속). HashiCorp 공식 문서 명령 그대로.
  - 구체 backend 설정값(bucket·DynamoDB table 이름 등)은 환경 의존이라 예시로만 표기, 실제 값 박지 않음.
- **실패/미완성**: 실 환경 검증 미수행(환경 부재). backend 전환은 사용자 환경에 맞춰 선택.
- **남은 작업**:
  - 사용자 환경에서 선택한 backend 확정 → README 예시 교체.
  - CI 도입 시 `-out=tfplan` 산출물 보관 정책 결정.
- **중복 방지 메모**: state lock·dependency lock·backend 한계는 terraform/README.md 한 섹션에만. 다른 곳에 다시 풀어 쓰지 말 것.
- **주의사항**:
  - `terraform force-unlock` 은 lock holder가 실제로 돌고 있지 않을 때만 — 동시 실행 중 force-unlock 하면 state 파괴 위험.
  - `-lock=false` 사용 금지.
  - remote backend 도입 시 credential은 backend별 표준 메커니즘(AWS env, GCP ADC 등)으로만 — 코드/git 금지.

---

## 2026-05-24 — terraform/ multi-stack 패턴 + .gitignore 보강

- **상태**: DONE
- **한 일**:
  - `terraform/README.md` (삭제됨) 재정리. quick start를 3 단계로 분리:
    (1) 오프라인 mirror 준비 + 결과 트리 검증, (2) `stacks/connection/` 만들기 (provider 접속/공통 outputs 한 곳), (3) `stacks/orgs/` 만들기 (`data "terraform_remote_state"` 로 connection outputs 참조 + 시크릿은 `TF_VAR_*` env로만 주입).
  - 대안으로 공통 tfvars 공유 패턴(`stacks/_shared/connection.tfvars`)도 짧게 기재.
  - 모든 코드 블록을 **그대로 복사·실행 가능한 bash heredoc** 형태로 통일. HCL 파일 내용은 `cat > file << 'EOF' ... EOF`로 생성 (작은따옴표 sentinel로 셸 치환 차단).
  - 이전 버전에서 깨져 있던 `cat << EOF >` 누락·블록 펜스 누락·HCL/bash 혼재 모두 정정.
- **픽스한 내용**:
  - [.gitignore](../.gitignore) 보강 — `terraform/**/.terraform/`, `terraform/**/terraform.tfstate*`, `*.auto.tfvars`, `terraform/providers/mirror/` 제외. `.terraform.lock.hcl`은 의도적으로 커밋(해시 핀, 시크릿 없음).
- **수정한 파일**: `terraform/README.md` (삭제됨), [.gitignore](../.gitignore), [worklog.md](worklog.md)
- **검증**:
  - heredoc 종결 / 코드 블록 펜스 / 변수 인용 모두 수동 확인.
  - `terraform_remote_state` 패턴은 표준 Terraform 기능 (provider 비종속).
  - `vmware/vcfa` 리소스 인자(예: `vcfa_org`의 `name`/`display_name` 등)는 본 README에 박지 않고 upstream Registry 페이지로 링크 — 인자명을 추측해 적지 않기.
- **실패/미완성**:
  - 실제 `terraform/stacks/{connection,orgs}/` 파일은 아직 생성하지 않음 — README가 절차이므로 사용자 환경값으로 실행 시 생성됨.
  - VCFA 환경에서 `terraform init` ~ `apply` 까지 실 검증은 환경 부재로 미수행.
- **남은 작업**:
  - 사용자가 한 번 실행해본 뒤 실제로 만들어진 파일을 리포에 커밋할지 결정.
  - `stacks/roles/`, `stacks/content-libraries/` 추가 시 동일 패턴 적용.
- **중복 방지 메모**:
  - Terraform multi-stack 패턴 표준은 `terraform_remote_state` (1순위) / 공통 tfvars (2순위). 다른 패턴 도입 시 사유 기록.
  - 시크릿은 항상 `TF_VAR_*` env로만. 파일·tfvars·git 어디에도 금지.
- **주의사항**:
  - `terraform.tfvars`에 비-시크릿(`vcfa_url`, `vcfa_user`)은 들어가도 됨. password/token은 절대 금지.
  - `*.auto.tfvars`는 이름만 맞으면 자동 로드되므로 사고 위험 → 본 리포에서는 `-var-file` 명시 사용 권장 (gitignore도 그에 맞춤).

---

## 2026-05-24 — 폴더별 README + REST 자동화 절 추가, 사용자 피드백 반영

- **상태**: DONE (사용자 피드백 반영 결과 — 이전 자기 작업의 잘못된 추정 정정 포함)
- **한 일**:
  - 각 자산 폴더에 quick start를 가진 README 신설/재작성:
    - [blueprints/README.md](../blueprints/README.md) — Cloud Assembly Test/Release 절차
    - [forms/README.md](../forms/README.md) — Custom Form Import 절차, 짝 매핑
    - [actions/README.md](../actions/README.md) — 패키지/개별 등록 + REST 포인터
    - [packages/README.md](../packages/README.md) — UI + **`POST /vco/api/packages` curl 패턴** (vRO 8.x 표준, VCFA 환경 검증 포인트 명시)
    - `terraform/README.md` (삭제됨) — `vmware/vcfa` provider scope를 upstream 가이드 직접 인용으로 확정 (`vcfa_org` / `vcfa_org_local_user` / `vcfa_content_library` / `vcfa_role` / `vcfa_global_role` / `vcfa_rights_bundle` / data sources `vcfa_right` 등)
  - 최상위 [README.md](../README.md)를 폴더 인덱스 + 매칭표 중심으로 슬림화. "빠른 시작 = 산출물 임포트 가능한 상태까지", 운영 절차는 runbook으로 분리.
  - offline-setup runbook에 `vmware/vcfa` 단일 provider 기준 + provider 인증 블록 + 환경변수 + `-platform` 옵션 + lock 파일 이전 항목 보강.
- **픽스한 내용** (이전 작업의 잘못된 추정을 사용자가 지적 → 정정):
  - 잘못 박았던 generic provider 예시(`hashicorp/vsphere`, `vmware/vcd`, `vmware/nsxt`)를 모두 제거 — 이 리포는 VCFA 전용.
  - "Terraform이 본 워크플로우와 무관할 수 있다"는 잘못된 추측 철회 — VCFA 관련이면 Terraform도 명시적으로 포함. `terraform/`는 분류일 뿐 범위 제외 아님.
  - "빠른 시작"에 UI 5단계 + 입력+Submit까지 묶었던 것을 정정 → 빠른 시작은 임포트 가능한 상태까지, 그 이후 절차는 runbook으로.
- **수정한 파일**:
  - 신설: `blueprints/README.md`, `forms/README.md`, `actions/README.md`, `packages/README.md`
  - 갱신: `README.md`, `terraform/README.md`, `docs/runbooks/offline-setup.md`
- **검증**:
  - Terraform provider 사실(`vmware/vcfa`, version `~> 1.1.0`, VCFA 9+ 지원, 인증 인자, 환경변수, 리소스/데이터 소스 이름)은 사용자가 알려준 upstream URL을 직접 fetch해 인용. [importing_resources](https://registry.terraform.io/providers/vmware/vcfa/latest/docs/guides/importing_resources), [roles_management](https://registry.terraform.io/providers/vmware/vcfa/latest/docs/guides/roles_management), `vmware/terraform-provider-vcfa` README 및 `docs/index.md`.
  - 폴더별 README의 내부 상대 링크 깨짐 검사 — 모두 해석됨.
  - REST 자동화 curl 예시는 vRO 8.x 표준 `POST /vco/api/packages` 패턴까지만 확정 게재. **VCFA 9 번들 Orchestrator의 base URL prefix와 인증 헤더는 라이브 검증 환경 없어 "확인 필요"로 명시.** 권장 검증 절차(브라우저 DevTools로 UI 호출 캡처)도 함께 기재.
- **실패/미완성**:
  - VCFA 번들 Orchestrator의 정확한 REST 엔드포인트/인증 헤더 미검증. 사용자가 실 환경에서 캡처해 확정 후 packages/README 갱신 권장.
- **남은 작업**:
  - VCFA에 적합한 토큰 발급 API 명시 (현재 자리만 잡힘).
  - terraform/stacks/ 하위 구조(예: `orgs/`, `roles/`, `content-libraries/`) 도입 여부 결정.
- **중복 방지 메모**:
  - 자산 quick start는 각 폴더 README 한 곳에만. 최상위 README/runbook에 같은 내용 다시 쓰지 말 것.
  - Terraform provider 예시는 항상 `vmware/vcfa` 만. 다른 provider 추가는 사용자 명시 요청 시에만.
- **주의사항**:
  - REST/curl 예시의 인증 헤더·base URL은 환경에 따라 다르므로 그대로 사용 금지 — 캡처 후 교체.
  - 시크릿(비밀번호·토큰)은 절대 커밋 금지, 환경변수/vault로만 주입.

---

## 2026-05-24 — README 예시 중심으로 재작성

- **상태**: DONE
- **한 일**: README를 산문 설명형 → **명령/경로 예시 중심**으로 교체. 폴더 트리·매칭표·자주 바꾸는 입력·`terraform providers mirror` 예시 포함. Terraform 자동화 부재를 명시("직접 채워야 함").
- **수정한 파일**: [README.md](../README.md)
- **검증**: 링크 5개 대상 실재 확인(`blueprints/vm/*`, `forms/vm/*`, `forms/cluster/*`, `terraform/providers/`, `docs/runbooks/offline-setup.md`).
- **중복 방지 메모**: 디테일은 docs/runbooks/* 에만. README에 절차를 다시 풀어 쓰지 말 것.

---

## 2026-05-24 — 폴더 유형별 재배치 + 오프라인/배포 런북

- **상태**: DONE
- **한 일**:
  - 루트에 흩어져 있던 자산을 유형별 폴더로 이동(`blueprints/{vm,cluster,archive}/`, `forms/{vm,cluster,archive}/`, `packages/`). `git mv`로 이력 보존.
  - `actions/` 는 vRO 모듈 ID와 일치하므로 그대로 유지(`com.vmk`, `com.vmk.dk`).
  - 오프라인 Terraform 산출물 위치 마련: `terraform/providers/` + 설명 `terraform/README.md`.
  - 런북 2종 추가: [docs/runbooks/offline-setup.md](runbooks/offline-setup.md) (TF provider 오프라인 미러·서명 검증·시크릿 처리), [docs/runbooks/deploy.md](runbooks/deploy.md) (어디를 수정 → vRO/CA/SB import → 배포 → 트러블슈팅).
  - README/context/architecture/security/tech-debt의 경로·링크를 새 구조로 일괄 갱신.
- **픽스한 내용**: 코드/블루프린트 본문은 변경 없음. 파일 이동 + 문서만.
- **수정한 파일**:
  - 이동(10): `blueprint_*.yaml` → `blueprints/{vm,cluster,archive}/`, `custom_*.yml` → `forms/{vm,cluster,archive}/`, `com.dk.package` → `packages/`
  - 신설: `terraform/README.md`, `docs/runbooks/offline-setup.md`, `docs/runbooks/deploy.md`
  - 갱신: [README.md](../README.md), [docs/context.md](context.md), [docs/architecture.md](architecture.md), [docs/security.md](security.md), [docs/tech-debt.md](tech-debt.md)
- **검증**:
  - `git status` 가 모든 이동을 `R` (rename)로 인식 — 이력 보존 확인.
  - 블루프린트는 `$data` URL 경로만 사용(로컬 cross-ref 없음)이므로 폴더 이동이 동작에 영향 없음을 사전에 grep으로 확인.
  - README/문서 내 새 링크 대상이 실재함을 폴더 재배치 후 `ls`로 확인.
  - vRO/Cloud Assembly import·실제 배포는 **검증하지 않음** (해당 환경 없음).
- **실패/미완성**: 없음.
- **남은 작업**:
  - 중복 [forms/archive/custom_vra_cluster.yml](../forms/archive/custom_vra_cluster.yml) 삭제 여부 결정 (사용처 확인 후).
  - `*_original` 백업 보존 정책 결정 → `docs/decisions/`.
  - Terraform 실제 HCL 코드가 추가되면 `terraform/stacks/` 등 하위 구조 결정.
  - 오프라인 미러를 git에 둘지 외부 아티팩트 저장소에 둘지 결정.
- **중복 방지 메모**:
  - 폴더 구조는 이미 재배치 완료. 다시 만들지 말 것. 새 자산은 유형에 맞는 기존 폴더에 추가.
  - 런북은 `runbooks/`에 새 파일을 만들기보다 기존 두 개를 갱신할 것.
- **주의사항**:
  - `actions/com.vmk.dk/` 파일명/구조는 vRO 액션 ID와 일치 — rename·이동 금지(블루프린트의 `$data` URL이 깨짐).
  - provider 바이너리·시크릿은 커밋 금지.

---

## 2026-05-24 — 문서 인프라 초기 셋업

- **상태**: DONE
- **한 일**:
  - `docs/` 디렉터리 신설 (context, architecture, security, tech-debt, worklog)
  - README.md를 한 줄짜리에서 사용법 중심 개요로 교체
  - 리포 내 직접 확인된 사실만 기재 (블루프린트/폼 파일 수, vRO 액션·매니저 목록, 비밀번호 보호 속성, 중복 파일)
- **픽스한 내용**: 해당 없음 (코드 변경 없음, 문서 신설만)
- **수정한 파일**:
  - `README.md` (교체)
  - `docs/context.md` (신설)
  - `docs/architecture.md` (신설)
  - `docs/security.md` (신설)
  - `docs/tech-debt.md` (신설)
  - `docs/worklog.md` (신설, 본 엔트리)
- **검증**:
  - 모든 사실은 직접 파일을 읽거나 명령(`wc -l`, `diff -q`, `unzip -l`, `file`)으로 확인.
  - vRO 런타임 동작은 검증하지 않음 (이 환경에 vRO 인스턴스 없음).
- **실패/미완성**: 없음
- **남은 작업** (다음 세션에서 결정):
  - `custom_cluster.yml` ↔ `custom_vra_cluster.yml` 중복 해소 (사용처 확인 후)
  - `*_original.*` 보존 정책 결정 → 결정 시 `docs/decisions/`에 기록
  - vRO 액션 파일명 오타(`Stroage`, `getUbuntuVersion` 확장자 누락) 정리 여부 — vRO 측 액션 ID 호환성 확인 필요
- **중복 방지 메모**:
  - `docs/` 구조와 README는 이미 설정됨. 다음 세션에서 다시 생성하지 말 것.
  - 코드/블루프린트는 본 작업에서 **건드리지 않음** — 사용자 명시 요청 전까지 그대로 유지.
- **주의사항**:
  - 새 문서/엔트리 추가 시 추측 금지. 확인되지 않은 내용은 "미확인"으로 명시.
  - 비밀(시크릿/토큰/평문 비밀번호)을 로그·문서·예시에 포함하지 말 것.

---

## 2026-05-24 17:00 — Tenant 모드 + Blueprint/Form/CCI/Package 자동화 (보류)

### 추가/검증된 함수

**`scripts/vcfa-api-lib.sh`**:
- `login_vcfa_tenant` + dispatcher `login_vcfa` (`VCFA_TENANT_ORG` 트리거)
- `vcfa_list_projects` / `vcfa_select_project` (tenant 전용)
- `_vcfa_list_namespaces_cci_json` — tenant 모드용 CCI 우회 (cloudapi VDC 가 403 이라)
- `vcfa_namespace_show_limit_cci` / `vcfa_namespace_set_limit_cci` / `vcfa_namespace_set_storage_limit_cci`
  - CCI PATCH (`application/merge-patch+json`) 로 UI 와 동기화. CPU/Mem/Storage 모두 검증 완료.

**`scripts/vcfa-content-lib.sh`**:
- `bp_remote_list` / `bp_remote_get` / `bp_remote_import` / `bp_remote_export` / `bp_remote_delete`
- `bp_select_export [sub-dir]` — 대화식
- `catalog_remote_list`
- `form_remote_import` / `form_remote_export` / `form_remote_delete`
- `form_select_export` — 대화식 (form-id 사용자 입력 필요 — server list endpoint 없음)
- `content_publish FILE [FORM]` — import → release → form (자동 체이닝, `VCFA_BP_ID/CATALOG_ITEM_ID/FORM_ID` env export)
- `content_publish_all [--include-archive] [--cleanup-on-fail]` — 모든 운영 파일 일괄

**`scripts/vcfa-vro-package-lib.sh`**:
- `vco_package_sync_module PACKAGE MODULE` — 패키지에 누락된 모듈 action 자동 동기화. 기존 서명 .package 를 base 로 unsigned element 추가 → partial-signed import (vRO 가 받아들임, 검증 완료).
- `vco_package_details` — JSON 원본 대신 표 형식 출력 (패키지/인증서/element 표/요약 카운트). `--raw` 로 원본 JSON.

**`scripts/session.sh`**: env 파일 인자 지원 (`source scripts/session.sh .env.tenant`). 전환 시 선택 상태 (TOKEN, ORG, PROJECT, NS) 자동 unset.

### .env / .env.tenant 핵심
- `.env`: provider — `VCFA_USER=admin@system`
- `.env.tenant`: tenant — `VCFA_USER=configadmin`, `VCFA_TENANT_ORG=ProviderConsumptionOrg` (분기 트리거)

### 핵심 검증 사실 (2026-05-24)
1. **Tenant 모드 = ORG 내부 API 자동화 키** — Cloud Assembly 의 blueprint/form, project-service, catalog, CCI 모두 project-scoped RBAC 으로 보호됨 → provider 토큰은 403/500, **project 멤버 tenant user 토큰은 200**.
2. **CCI namespace 한도 = tenant 모드의 `*_cci` 함수만 UI 와 동기화**. cloudapi PUT 은 백엔드만 갱신.
3. **vRO 액션/패키지 = 양쪽 모드 모두 작동** — 환경 전역 자산.
4. **vRO 패키지 멤버 추가는 partial-signed 우회법으로 가능** — 이전 결론 "REST 불가" 정정.
5. **Form 서버 list endpoint 없음** — `/forms/{uuid}` 단건 GET 만. form-id 추적은 사용자 책임 (import 직후 `VCFA_FORM_ID` env 활용).

### 보류 — 환경 측 문제 (다음 세션에서 재확인)
**`bp_remote_release` 가 HTTP 400** 으로 실패:
```
{"message":"VRO action com.vmk.dk/getProjectsNames not found", ...}
```
- vRO 자체에 `com.vmk.dk/getProjectsNames` 액션은 존재 (vco_list_actions 로 17개 모두 확인).
- Cloud Assembly 가 release 검증 시 사용하는 vRO action lookup 경로에서 못 찾음.
- 같은 입력으로 이전 (15:00 / 15:07 / 15:12 / 15:49) 에는 release 성공 → **환경 측 일시적 cache stale** 추정.
- 사용자가 UI 에서 확인 부탁한 상태 (Cloud Assembly UI 의 Embedded vRO integration sync 또는 새 blueprint Test 로 dropdown 채워지는지).

### 다음 세션 진입 시
1. `source scripts/session.sh .env.tenant`
2. `bp_remote_list` / `catalog_remote_list` 확인 — 환경 측 풀렸으면 release 재시도 가능
3. release 가 작동하면 즉시 `content_publish_all` 로 일괄 import 검증
4. `bp_select_export` / `form_select_export` 검증
5. release 가 계속 400 이면 → Cloud Assembly UI 에서 vRO integration sync 또는 Test dropdown 확인 → 결과 보고 추가 진단

### 현재 서버 상태
- com.vmk.dk 모듈: 17개 액션 (정상)
- com.dk 패키지: 2개 element (`vco_package_sync_module com.dk com.vmk.dk` 한 번 더 돌리면 17개)
- blueprint: 0개 (DRAFT 모두 정리됨)
- catalog item: 0개
- namespace vcfa-kc5tn: 100 GHz / 100 GiB / 3.0 TiB (이전 검증 후 원복 상태)

### 관련 메모리 / 문서
- [reference_vcfa_cci_api.md] — CCI = tenant 모드에서 작동 (자동화 가능)
- [README.md] — 사용법 요약
- [docs/api-reference-guide.md] — 검증된 endpoint 모음

---

## 2026-06-25 — VCF 9.x: $data 액션 동작불능 진단·해결 + 폼 실증 (라이브 검증)

- **상태**: DONE (vCenter/vAPI 등록은 보류 — 자격증명 필요)
- **배경**: 폼 드롭다운 대부분이 동작 안 함. getProjectsNames RUN → "No VCFA:Host objects found".
- **근본 원인 (라이브 vcfa.dtvcf.lab 진단)**:
  1. `com.vmk.dk` `$data` 액션은 VCF 9.x All-Apps 모델(`VCFA:Host`/`cciService`)로 올바르게 작성돼 있었으나 **Orchestrator 인벤토리에 VCFA:Host 미등록** → throw. (코드 문제 아님)
  2. import 헬퍼가 `runtime` 미설정 → **Python 액션 3개(ChangePasswordHash·doubleBase64·validatePasswordMatch)가 JS로 import되어 깨짐.**
- **한 일**:
  - `vco_import_action`: `.js` 안 `def handler` 자동 감지 → `runtime=${VCO_PY_RUNTIME:-python:3.10}` (검증: 3개 모두 `runtime:python:3.10`).
    > **[정정 2026-06-26]** 9.1 에서 `python:3.10` 단종 → 기본값 **`python:3.11`** 로 변경. 라이브/패키지 3개 모두 `python:3.11` 확인.
  - 신규 헬퍼: `vco_run_workflow`(워크플로 실행+폴링), `vcfa_register_host`(VCFA:Host 등록, .env 자동), `vco_run_action`(vRO 액션 직접 실행 REST `POST /vco/api/actions/<m>/<n>/executions`).
  - **VCFA:Host 등록** — `Add a VCF Automation Host` 워크플로. 결정타: **`connectionType="Per User Session"`** (Shared Session 은 `fetchAll Project` 실패), `k8sApiVersion=v1alpha2`. → 검증된 기본값으로 헬퍼에 박음.
    > **[정정 2026-06-26, 이 항목은 아래 '이어서2' 로 대체됨]** 카탈로그 **폼** 드롭다운까지 되려면 **`connectionType="Shared Session"` + 지속 API 토큰(`VCFA_HOST_API_TOKEN`)** 이 정답. `Per User Session` 은 vRO 직접 RUN 만 되고 폼은 무한로딩(서비스 컨텍스트엔 per-user 세션 없음). 라이브 호스트(`vcfa-auto`)는 Shared Session 으로 정상 동작 확인. 헬퍼 기본값도 토큰 있으면 Shared Session 자동.
  - 코드 버그: getKRVersion 중복(v1.34.1) 제거, getStorageClass `|| []` 가드, getProjectsNames/getNamespaces actionable 에러문구.
- **수정한 파일**: `scripts/vcfa-vro-package-lib.sh`, `actions/com.vmk.dk/{getProjectsNames,getNamespaces,getKRVersion,getStorageClass,ChangePasswordHash,doubleBase64,validatePasswordMatch}.js`
- **검증 (라이브, vco_run_action 으로 실제 실행)**:
  - getProjectsNames=`["vcfa2","default-project","vcfa1"]`, getNamespaces(default-project)=`["hh-ns-zqbhb","vcfa-7f4cv"]`, Python·하드코딩·storage 액션 OK.
  - **vm 폼 바인딩 확인**(form id 9f131743, status ON) + 드롭다운 11개 중 **10개 데이터 반환**. getVMImage 만 ✗(vAPI endpoint 미등록), getStorageClass 는 k8s만(vCenter 미등록).
  - com.vmk(5)·com.vmk.dk(17) 둘 다 등록 확인. com.vmk 로컬==서버.
- **남은 것 (자격증명 필요)**:
  - getVMImage → `Add vAPI endpoint`(`9fa581be-…`), getStorageClass 확장 → `Add a vCenter Server instance`(`f246b7b5-…`).
  - **`com.vmk.tool`·`com.vmk.driver` 모듈이 서버·리포 모두 부재** → NsxtManager/VcsaManager/VraManager 런타임 실패(배포-시점 헬퍼). VraManager 는 9.x All-Apps 비호환(별도 재작성 필요).
- **중복 방지 메모**: 액션 import 는 `vco_import_data_actions`(JS $data) + `vco_run_action`(검증). com.vmk 은 **재import 금지**(input-parameters 보존 — 이미 서버==리포). 호스트 등록은 `vcfa_register_host`.

---

## 2026-06-25 (이어서) — vCenter/vAPI 등록 + 폼 드롭다운 전수 검증 (라이브)

- **상태**: DONE (getStorageClass PBM·getVMImage 라이브러리는 환경/콘텐츠 이슈로 보류)
- **한 일**:
  - 신규 헬퍼: `vco_run_action`(vRO 액션 직접 실행 REST), `vcfa_register_vcenter`, `vcfa_register_vapi`. `.env` 에 `VC_HOST/VC_USER/VC_PASS[/VC_PORT/VC_IGNORE_CERT/VAPI_ENDPOINT_URL]` 키 추가(example 2개).
  - **vCenter**(`vcsa01.dtvcf.lab`) + **vAPI endpoint** + **vAPI metamodel**(`Import vAPI metamodel` 9eee7150) 등록 완료. (내가 예시로 준 `vcenter.dtvcf.lab` 은 DNS 없음 — provider API `/cloudapi/1.0.0/virtualCenters` 로 실주소 확인)
  - getStorageClass: `VcPlugin.allSdkConnections`(세션-스코프, 빈값) → `Server.findAllForType("VC:SdkConnection")` 폴백 추가.
- **수정한 파일**: `scripts/vcfa-vro-package-lib.sh`, `actions/com.vmk.dk/getStorageClass.js`, `.env.example`, `.env.tenant.example`
- **검증 (vco_run_action, 라이브)**: 폼 드롭다운 11개 중 **10개 데이터 반환**. com.vmk(5)·com.vmk.dk(17) 등록 확인, vCenter 연결 dumpVcRoots 로 확인.
- **남은 2개 (환경/콘텐츠 — .env/스크립트 영역 아님)**:
  - **getVMImage**: vAPI+metamodel OK, 단 폼이 찾는 Content Library `vra-image` 가 vCenter 에 없음(존재: avi / licensehub-ssp-content-lib / Custom Kubernetes Service / Supervisor Images / Kubernetes Service). → 라이브러리 생성 또는 폼 `targetLibraryName` 변경.
  - **getStorageClass**: vCenter 연결 OK + PBM 정책 19개 존재하나 액션의 `pbmProfileManager.pbmQueryProfile` 가 빈값(k8s 폴백만 반환). vCenter 플러그인 PBM 스크립팅 9.x 호환 의심 — 별도 조사.
- **중복 방지 메모**: vCenter/vAPI 등록 = `vcfa_register_vcenter`/`vcfa_register_vapi`(+ `Import vAPI metamodel`). 등록 멱등 아님(중복 주의). smsUrl 은 비워둘 것(잘못된 값이면 302로 Add 실패).

---

## 2026-06-25 (이어서2) — 카탈로그 폼 무한로딩 해결: Shared Session + 지속 API 토큰

- **상태**: DONE
- **증상**: 폼 드롭다운이 vRO 직접 실행은 되는데 **카탈로그 요청 폼에서만 무한로딩**.
- **원인 2겹**:
  1. **getVMImage 가 throw**(vra-image 라이브러리 없음) → 폼-서비스의 탭 데이터 평가가 통째로 깨져 전 드롭다운 로딩. → getVMImage/getProjectsNames/getNamespaces 를 throw 대신 `[]` 반환으로 견고화.
  2. **VCFA:Host 가 `Per User Session`** → 카탈로그는 서비스 컨텍스트라 per-user 세션이 없어 빈값. `Shared Session` 이 필요한데 **저장 apiToken 이 만료성 access token 이면 fetchAll 실패**. → **VCFA 콘솔 UI 에서 API 토큰 발급**(API 로는 403/400 거부) → `.env` 의 `VCFA_HOST_API_TOKEN` 으로 주입 → Shared Session 으로 갱신 → getProjectsNames 실값 확인.
- **한 일**:
  - `vcfa_register_host`: 기존 호스트면 Update 자동, `VCFA_HOST_API_TOKEN` 있으면 Shared Session 자동 선택, apiToken 우선순위(API토큰>세션토큰).
  - `.env` 키 추가: `VCFA_HOST_API_TOKEN` (지속 VCFA API 토큰).
  - getVMImage/getProjectsNames/getNamespaces: 모든 오류 경로 throw→`[]`.
- **수정한 파일**: `scripts/vcfa-vro-package-lib.sh`, `actions/com.vmk.dk/{getVMImage,getProjectsNames,getNamespaces}.js`, `.env*.example`
- **검증(라이브)**: Shared Session + API토큰 → getProjectsNames=`["vcfa2","default-project","vcfa1"]`, getNamespaces=`["hh-ns-zqbhb","vcfa-7f4cv"]`. (사용자 UI 폼 재확인 대기)
- **남은 것(콘텐츠)**: getVMImage=vCenter 에 `vra-image` 라이브러리 생성 필요, getStorageClass=PBM 정책 안 옴(9.x 플러그인 호환 의심).

---

## 2026-06-26 — getVMImage CCI 전환 (vra-image 하드코딩 제거, VM Image 드롭다운 해결)

- **상태**: DONE (라이브 검증 완료)
- **증상**: 카탈로그 폼의 **VM Image 드롭다운이 빈값**("vm image 를 못찾네").
- **근본 원인**: `getVMImage` 만 유일하게 옛 경로(`VAPIManager`→vCenter Content Library) + 폼/블루프린트가 `targetLibraryName=vra-image` **하드코딩**. 그런데 이 vCenter 엔 `vra-image` 라이브러리가 없음(존재: avi/Supervisor Images/Kubernetes Service/Custom Kubernetes Service/licensehub-ssp-content-lib) → `[]` 반환. 형제 액션(getVMClass/getContentsLibrary/getKRVersion 중 앞 2개)은 이미 CCI 로 이전됐는데 이것만 누락.
- **라이브 확인 (테넌트 토큰, 읽기 전용)**:
  - 배포 가능한 VM 이미지 = **`ClusterVirtualMachineImage`** (cluster-scoped) 27개. `metadata.name=vmi-<hash>`, `status.name=친근명`(예: `ob-25217799-ubuntu-2404-amd64-v1.35.0---vmware.2-vkr.4`). 27/27 status.name 유일.
  - **CRD 스키마(openapi)**: `VirtualMachine.spec.imageName` 은 `vmi-오브젝트명` **또는 display name(=status.name)** 둘 다 허용(display name 은 단일 식별 시 웹훅이 resolve). → 친근명을 값으로 쓰면 배포 OK + 폼 `contains: ubuntu/photon` 가시성·`getAdminUserByImage` OS추론 그대로 유지.
  - 네임스페이스 범위 `virtualmachineimages` 와 `virtualmachines` 는 테넌트 RBAC 로 403(클러스터 이미지는 200) — cluster 목록이 전 네임스페이스 공통이라 충분.
- **한 일**:
  - `getVMImage.js` 재작성: `getContentsLibrary` 와 동일한 `host.createRestClient()`→CCI 프록시. 입력 없음. `…/apis/vmoperator.vmware.com/v1alpha3/clustervirtualmachineimages`(v1alpha2 폴백), label=value=`status.name`. 모든 오류 경로 `return []`.
  - 폼 2개(`custom_vm.yml`, `custom_vm_storageclass_manual.yml`) `image.valueList.parameters` → `[]`. 블루프린트 2개 `$data: …/getVMImage`(쿼리 제거).
  - 문서 정리: deploy.md/clean-reupload.md/context.md/api-reference-guide.md/clean-deploy.sh 에서 "getVMImage=vAPI/`vra-image`" 표기 제거. **vAPI(VAPIManager) 의 유일한 잔여 사용자는 `getKRVersion`(클러스터 블루프린트)** 로 정정.
- **수정한 파일**: `actions/com.vmk.dk/getVMImage.js`, `forms/vm/{custom_vm,custom_vm_storageclass_manual}.yml`, `blueprints/vm/{blueprint_vm,blueprint_vm_storageclass_manual}.yaml`, `docs/{context.md,api-reference-guide.md,runbooks/deploy.md,runbooks/clean-reupload.md}`, `scripts/clean-deploy.sh`
- **검증 (라이브)**: 새 시그니처(Array/Properties, 입력 없음)로 `vco_import_action` PUT 200 → `vco_run_action com.vmk.dk/getVMImage` = **27개 이미지 반환**(정렬된 친근명 목록).
- **중복 방지 메모**: VM Image 소스는 이제 **CCI clustervirtualmachineimages**(vAPI/Content Library 아님). 빈값이면 VCFA:Host/토큰 점검. import 는 `vco_import_action … Array/Properties '[]'`.

---

## 2026-06-26 (이어서) — getKRVersion 도 CCI 전환 → vAPI(VAPIManager) 의존 완전 제거

- **상태**: DONE (라이브 검증 완료)
- **배경**: 위에서 getVMImage CCI 전환 후, vAPI 의 유일한 잔여 사용자가 `getKRVersion` 뿐이었음. 사용자 요청("진행해줘")으로 마저 이전.
- **사전 비교(안전 확인)**: `clustervirtualmachineimages`.status.name 에서 vkr 패턴 추출 결과 = 현재 라이브 getKRVersion(VAPIManager) 출력과 **8개 완전 동일**(v1.32.10~v1.35.2). → 결과 불변, 안전.
- **한 일**:
  - `getKRVersion.js` 재작성: getVMImage 와 동일 CCI 패턴(host.createRestClient → `…/vmoperator.vmware.com/v1alpha3/clustervirtualmachineimages`, v1alpha2 폴백). status.name 에서 `v\d+\.\d+\.\d+---vmware\.\d+(-fips)?-vkr\.\d+` 추출·dedup, label=`vX.Y.Z`/value=full, 버전 오름차순. **시그니처(ProjectName,NamespaceName 입력)는 보존** → 클러스터 블루프린트 `$data` 바인딩 무수정.
  - 문서 재정정: clean-reupload.md/deploy.md/clean-deploy.sh — "vAPI=getKRVersion" → **어떤 $data 액션도 vAPI 미사용**, `vcfa_register_vapi` 는 선택/레거시로 강등(호출은 `|| true`).
- **수정한 파일**: `actions/com.vmk.dk/getKRVersion.js`, `docs/runbooks/{clean-reupload.md,deploy.md}`, `scripts/clean-deploy.sh`
- **검증 (라이브)**: `vco_import_action`(Array/Properties + ProjectName/NamespaceName) PUT 200 → `vco_run_action getKRVersion (ProjectName=default-project NamespaceName=vcfa-7f4cv)` = **8개**, 무인자 호출도 8개. 기존 출력과 동일.
- **블루프린트/폼 라이브 동기화(미실행, 선택)**: getVMImage 폼/블루프린트의 `targetLibraryName=vra-image` 제거분은 **재배포 없이도 라이브 정상**(라이브 액션이 미선언 파라미터 무시 → 옛 바인딩으로 호출해도 27개 반환 검증). 메타데이터 정리(옛 param 제거)는 `content_publish` 로 재배포 시 반영되나, 블루프린트 삭제·재생성이라 보류. 필요 시 `content_publish blueprints/vm/blueprint_vm.yaml forms/vm/custom_vm.yml`.
- **중복 방지 메모**: 이제 `VAPIManager` 실사용 액션 0개(코드의 'VAPIManager' 문자열은 getKRVersion 주석의 이전이력뿐). vAPI 등록 불필요.

---

## 2026-06-26 (이어서3) — 클러스터 OS Image: 네이티브식 "버전→OS이미지(라이브러리 포함)" 캐스케이드

- **상태**: DONE (라이브 재배포 + 카탈로그 폼-컨텍스트 end-to-end 검증 완료).
- **요구**: 네이티브 클러스터 UI 의 OS Image 드롭다운(예 "Ubuntu 22.04 - Custom Kubernetes Service")처럼, KR 버전 선택 → 그 버전의 OS 이미지(라이브러리 구분 포함) 선택. windows=worker 전용.
- **핵심 발견 (라이브, 사용자 지적이 맞았음 — "vcfa는 잘 가져오던대")**:
  - clustervirtualmachineimages(27)는 전부 service 라벨이 `kubernetes.vmware.com` 라 라이브러리 구분 불가로 보였으나,
  - **`run.tanzu.vmware.com/v1alpha3/osimages`(OSImage)** 가 진짜 권위 소스. 라벨에 `content-library`(cl- id), `os-name`, `os-version`, `run.tanzu.vmware.com/kubernetesVersion` 보유.
  - content-library cl- 2종: `cl-06403f0697ec9b5c6`=**Kubernetes Service**(22), `cl-6bbf73cdd40a364df`=**Custom Kubernetes Service**(5). → Custom 도 자동화로 접근 가능(네이티브와 동일 재현).
  - namespace 범위 `virtualmachineimages` 는 테넌트·vRO 호스트 모두 403(불가). osimages 는 cluster-scoped 라 200.
  - join: getKRVersion 값에서 `-vkr.N` 제거 → OSImage `kubernetesVersion` 라벨과 일치(v1.35.2---vmware.1-vkr.3 → v1.35.2---vmware.1).
- **한 일**:
  - 신규 액션 **`getOSImageByKR.js`** (입력 krVersion, role). osimages → KR 필터 → 라벨 `"{OS} {ver} - {라이브러리}"`, **값 = resolve-os-image 셀렉터**(`os-name=…, content-library=cl-…[, os-version=…]`). role!=worker 면 windows 제외. cl→라이브러리명은 clustercontentlibraries 로 매핑.
  - 신규 **`getKRVersionManual.js`** (정적 KR 목록, 손편집용. getOS.js 식). 현재 8개 시드.
  - 클러스터 블루프린트/폼: 3필드(os/ubuntu_version/contents_library) → **OS Image 2필드(os_image_cp / os_image_worker)** 로 교체. CP=role controlplane(windows 제외), worker=role worker(windows 포함), 둘 다 `krVersion={{kr_version}}` 캐스케이드. `resolve-os-image` 는 CP=`${input.os_image_cp}`, worker 2풀=`input.os_image_worker`.
  - 임시 프로브 `dumpVMImages` repo·live 정리(DELETE 200).
- **수정/생성 파일**: `actions/com.vmk.dk/{getOSImageByKR,getKRVersionManual}.js`(신규), `blueprints/cluster/blueprint_vra_cluster.yaml`, `forms/cluster/custom_cluster.yml`
- **검증 (라이브)**: getOSImageByKR(POST 201). v1.35.2/controlplane=6개(스크린샷과 일치, Custom 포함), worker=+Windows 2022, v1.34.2=3개(custom 빌드 없음). getKRVersionManual=8개.
- **재배포 (DONE)**: tenant 세션(`source .env.tenant`+login) + `VCFA_BP_RECREATE=1` 로 `content_publish blueprints/cluster/blueprint_vra_cluster.yaml forms/cluster/custom_cluster.yml`. 옛 vra_cluster 삭제→재생성(id a613fe93…)→폼 set(4p)→release(v20260626.121750)→catalog(6c35e2ef…).
  - ★ provider(.env)로는 `_remote_guard`/RBAC 막힘 — **블루프린트/폼/카탈로그 publish 는 tenant(.env.tenant) 세션 필수**. 구조변경이라 update 아닌 RECREATE 필요(stale $data 인덱스 방지).
- **검증 (라이브, 블루프린트 data 엔드포인트=카탈로그 폼 경로)**: KR 8개 / os_image_cp(controlplane)=6개·windows 없음·Custom 포함(스크린샷 일치) / os_image_worker(worker)=+Windows 2022.
- **레이아웃 조정 (DONE, 재배포)**: KR Version 을 페이지1(기본설정)에서 → 페이지3 "8. Kubernetes / OS Image" 섹션 **맨 위**로 이동(그 아래 CP/Worker OS Image). 캐스케이드 의존(version→OS)대로 버전을 먼저 고르게. 클러스터 버전 1개가 CP·Worker OS Image 둘을 동시에 필터하므로 version-first 가 정답(OS-first 면 두 OS 와 호환되는 버전 교집합이라 복잡). 재배포 release v20260626.122407.
- **남은 것**: 사용자 UI 폼 최종 육안 확인. getOS·getUbuntuVersion·getContentsLibrary 는 클러스터 폼 미사용(액션 파일 보존).
- **중복 방지 메모**: OS 이미지/라이브러리/버전 권위 소스 = **OSImage(run.tanzu.vmware.com)**, NOT clustervirtualmachineimages(라이브러리 구분 불가)·NOT namespaced VMI(403). resolve-os-image 셀렉터 형식: ubuntu 만 os-version 포함.

---

## 2026-06-26 (이어서4) — getStorageClass(Optional) CCI 전환 (하드코딩 'k8s' 가짜값 제거) → vCenter 의존도 제거

- **상태**: DONE (라이브 검증).
- **증상**: Storage Class 드롭다운에 실재하지 않는 `k8s` 값만 노출.
- **원인**: `getStorageClass`/`getStorageClassOptional` 가 vCenter PBM(`pbmQueryProfile`) 조회 + **하드코딩 `k8s` push**. 9.x 에서 PBM 이 빈값이라 하드코딩 `k8s` 만 남음(라이브 확인: getStorageClass=`k8s` 1개).
- **한 일**: 두 액션을 CCI `status.storageClasses` 로 전환(검증된 `getStroageClassManual(Optionals)` 와 동일 패턴). PBM·`k8s` 제거. Optional 은 맨 앞 `__inherit__` 유지.
- **수정 파일**: `actions/com.vmk.dk/{getStorageClass,getStorageClassOptional}.js`, `docs/runbooks/{deploy.md,clean-reupload.md}`, `scripts/clean-deploy.sh`
- **검증 (라이브)**: import PUT 200 → getStorageClass=`obcluster-vsan-storage-policy`(실제값), getStorageClassOptional=`(상속)`+`obcluster-vsan-storage-policy`. (블루프린트 재배포 불필요 — 액션 import 만으로 드롭다운 갱신)
- **부수 효과**: getStorageClass 가 vCenter 의 마지막 $data 사용자였음 → **이제 폼 드롭다운 중 vCenter/PBM 사용 0개**(VcPlugin 은 진단 `dumpVcRoots` 만). vAPI 에 이어 **vCenter 등록도 선택/레거시**. 모든 드롭다운이 VCFA:Host(CCI) 만으로 동작.
- **중복 방지 메모**: Storage Class 소스 = CCI status.storageClasses(name=id). getStorageClass==getStroageClassManual 로 수렴(둘 다 CCI). vCenter 등록 불필요.
