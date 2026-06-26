# Runbook — 패키지/블루프린트/폼 전체 삭제 후 깨끗하게 재업로드

> **목적.** vRO 액션(패키지)·블루프린트·커스텀 폼을 한 번 싹 지우고, 검증된 소스(이 repo)에서
> 처음부터 다시 올려 **드롭다운이 정상 렌더링**되는 상태로 복구하는 7단계 절차.
> 검증된 사실(파일·함수명·output-type·`$data` 경로)은 단정하고, 외부 UI 동작은 "확인 필요"로 표기합니다.
>
> 일상 배포는 [deploy.md](deploy.md) 를 쓰세요. 이 문서는 **상태가 꼬였을 때의 wipe-and-reupload** 전용입니다.

전체 흐름:

```
[0] 로그인  →  [0.5] 사전 등록(Host/vCenter/vAPI)  →  [1] 백업
   │
   ▼
[2] UI: 블루프린트 + 커스텀 폼 삭제   →   [3] UI: 패키지 + 액션 삭제
   │
   ▼
[4] 패키지 import (액션 17개 복원)  →  [5] 블루프린트 import(신규)  →  [6] 폼 set(release 前) → release
   │
   ▼
[7] 드롭다운 렌더링 검증
```

---

## 권장 — 한 번에 실행: `scripts/clean-deploy.sh`

아래 7단계를 **검증·게이트까지 포함해 자동 수행**하는 스크립트가 있습니다. 손으로 단계를 밟기 전에
이걸 먼저 보세요. (UI 삭제(Step 2·3)는 사용자가 직접 하고, 그 뒤 import·등록·검증을 이 스크립트가 처리)

```bash
# (먼저) UI 에서 blueprint/form/package/actions 삭제 → 그다음:
bash scripts/clean-deploy.sh .env.tenant
```

이 스크립트가 자동으로 보장하는 것(아래 수동 절차의 함정 방지):
- **등록**(Host/vCenter/vAPI) — vCenter/vAPI 는 Add 전용이라 이미 있으면 "실패"해도 무시(정상).
- **FRESH 게이트** — 동명 blueprint 가 하나라도 남아 있으면 **중단**(stale `$data` 인덱스 방지). `VCFA_BP_CREATE_ONLY=1` 로 update 도 차단.
- **패키지 전용 import** — `vco_import_package` 만 사용(대체 경로는 타입을 Any 로 만들어 깨짐, 아래 Step 4 주의).
- **preflight** — release 前 `$data` output-type 점검.
- **검증** — 등록 3종 + 폼 컨텍스트 `{id,name}` + Python `python:3.11` 런타임 자동 확인.

수동으로 진행하려면 아래 단계를 그대로 따르세요. 각 단계에 동일한 안전장치를 주석으로 표시했습니다.

> 함수 정의 위치 — 인용한 모든 함수는 아래 lib 에 있습니다:
> - `scripts/session.sh` — 세션 로그인
> - `scripts/vcfa-vro-package-lib.sh` — `vco_export_package` / `vco_import_package` / `vco_list_actions` / `vco_import_action` / `vco_import_data_actions` / `vcfa_register_host` / `vcfa_register_vcenter` / `vcfa_register_vapi` / `vco_run_action`
> - `scripts/vcfa-content-lib.sh` — `bp_remote_import` / `bp_remote_release` / `bp_set_form` / `content_publish` / `bp_remote_delete` / `form_remote_delete` / `catalog_remote_list`

---

## Step 0 — 세션 로그인

REST/curl 헬퍼는 전부 `TOKEN` + `VCFA_FQDN` 을 셸에 두고 동작합니다. tenant org 토큰으로 로그인합니다.

```bash
source scripts/session.sh .env.tenant
```

- 성공하면 `OK: VCFA 세션 활성 (TOKEN length=...)` 출력.
- `.env.tenant` 가 없으면 `.env.tenant.example` 복사 후 `VCFA_USER`/`VCFA_PASS`/`VCFA_HOST_API_TOKEN`/`VC_*` 채우기.
- 이 user 는 **대상 project 의 멤버**여야 blueprint/form/catalog REST 가 200 (provider 토큰은 403/500).

---

## Step 0.5 — 사전 등록 (★ 패키지에 들어있지 않음, 빠지면 드롭다운이 빈값/에러)

**중요.** 아래 3개는 vRO **인벤토리 호스트 등록**이라 `.package` 안에 절대 포함되지 않습니다.
패키지만 import 하고 이걸 건너뛰면 `$data` 액션이 **빈 배열을 반환하거나 throw** 하고,
특히 `getVMImage` 는 vAPI 가 제공하는 `VAPIManager` 스크립팅 객체를 못 찾아 **실패**합니다.
`VAPIManager` 는 커스텀 액션이 아니고 패키지에도 없습니다 — vAPI endpoint 등록으로만 생깁니다.

```bash
vcfa_register_host       # VCFA:Host — getProjectsNames / getNamespaces 등의 소스
                         #   VCFA_HOST_API_TOKEN 있으면 connectionType="Shared Session" 자동(카탈로그 폼 동작),
                         #   없으면 "Per User Session"(직접 RUN 만 됨, 카탈로그 폼은 무한로딩). k8sApiVersion=v1alpha2.
vcfa_register_vcenter    # 밑단 vCenter — getStorageClass 의 스토리지 정책 소스 (.env: VC_HOST/VC_USER/VC_PASS)
vcfa_register_vapi       # vAPI endpoint + metamodel — getVMImage 의 Content Library/VM image 소스, VAPIManager 제공
```

| 등록 누락 시 증상 | 영향받는 드롭다운 |
| --- | --- |
| VCFA:Host 미등록 | Project / Namespace 등 전부 빈값 |
| VCFA:Host 가 `Per User Session` | 직접 RUN 은 되는데 **카탈로그 폼만 무한로딩** (서비스 컨텍스트라 per-user 세션 없음 → Shared Session 필요) |
| vCenter 미등록 | Storage Class 빈값 |
| vAPI 미등록 | VM Image 빈값 + `getVMImage` 가 `VAPIManager` 없어 실패 |

> ✅ **멱등 (probe-first).** 세 헬퍼 모두 **이미 등록돼 있으면 자동 생략**합니다 — 예전처럼 `state=failed ✗` 가 뜨지 않습니다.
> - `vcfa_register_host` : 동명 호스트가 있으면 **Update**.
> - `vcfa_register_vcenter` : 등록 前 `catalog/VC/SdkConnection` 조회 → `VC_HOST` 매치 있으면 `vCenter 이미 등록됨 — Add 생략`.
> - `vcfa_register_vapi` : 등록 前 `catalog/VAPI/VAPIEndpoint` 조회 → URL 매치 있으면 `vAPI 이미 등록됨 — Add/metamodel 생략`.
>
> 강제 재등록이 필요하면 `VCFA_FORCE_REGISTER=1` 을 붙여 실행. (참고: UI 에서 package/actions 만 지워도 Host/vCenter/vAPI 등록은 남으므로 보통 재등록 불필요.)

> ⚠ **VCFA_HOST_API_TOKEN 은 반드시 "지속(persistent) API 토큰".**
> 카탈로그 폼 드롭다운은 Host 가 `Shared Session` + 저장된 *지속* 토큰일 때만 동작합니다.
> 만료성 access token 이거나, `.env.tenant.example` 의 플레이스홀더(`여기에-...`)를 그대로 두면 —
> 값이 "있는" 것으로 간주돼 Shared Session 으로 등록되지만 토큰이 무효라 **모든 드롭다운이 조용히 빈값/무한로딩** 됩니다
> (패키지·블루프린트·폼은 멀쩡한데도). 토큰은 VCFA 콘솔 **User → API Tokens → Generate** 로 발급하세요.
> 증상(직접 RUN 은 되는데 카탈로그 폼만 빈값)이 보이면 토큰 만료 의심 → 재발급 → `.env.tenant` 갱신 → `vcfa_register_host` 재실행(Update).

> 사전 등록 검증:
> ```bash
> vco_run_action com.vmk.dk/getProjectsNames       # → ["vcfa2","default-project",...] (빈값이면 Host/토큰 문제)
> ```
> (이 검증은 **액션이 존재할 때**만 유효 — Step 3 에서 액션을 지운 뒤 ~ Step 4 import 전 구간엔 404 가 정상)

---

## Step 1 — 백업 (이번 세션에서 이미 완료)

이미 이번 세션에 패키지와 개별 액션 백업이 만들어져 있습니다. 재현용 명령만 적어 둡니다.

### 1-1. 패키지 백업

```bash
vco_export_package com.dk packages/com.dk.package
```

- 현재 파일: `packages/com.dk.package` (~58KB, com.vmk.dk 액션 17개 포함).
- 패키지는 import 시 **runtime 과 output-type 까지 충실히 복원**됩니다(패키지 XML 디코딩으로 검증). 즉 이 한 파일이 17개 액션의 코드+런타임+반환타입을 모두 담습니다.

### 1-2. 개별 액션 백업 (만약을 위한 평문 .js + 매니페스트)

개별 백업은 이미 `packages/actions-backup/com.vmk.dk/` 에 있습니다 (17개 `.js` + `_manifest.json`).
`_manifest.json` 은 각 액션의 `name / outputType / runtime / version / jsBytes` 를 담아 **Step 4 의 복원 검증 기준**으로 씁니다.

재현(개별 액션을 vRO 에서 다시 받아 백업하려면):

```bash
mkdir -p packages/actions-backup/com.vmk.dk
for n in $(vco_list_actions com.vmk.dk | awk 'NR>1{print $1}'); do
  vco_run_action _noop 2>/dev/null   # (참고: 개별 .js 본문은 repo 의 actions/com.vmk.dk/ 가 정본)
done
# 가장 단순한 정본 백업: repo 의 actions/ 가 라이브 vRO 와 17/17 동일하므로 그대로 보관
cp -a actions/com.vmk.dk/. packages/actions-backup/com.vmk.dk/
```

> 정본은 `actions/com.vmk.dk/*.js` 입니다 (라이브 vRO == 패키지 == repo, 17/17 동일 확인됨).
> `_manifest.json` 은 백업 시점의 메타 스냅샷이므로 그대로 둡니다.

---

## Step 2 — UI 에서 삭제: 블루프린트 + 커스텀 폼

> REST 로도 지울 수 있으나(아래 참고), 사용자는 **VCFA UI** 에서 진행합니다.
> 삭제 순서는 **폼 먼저, 블루프린트 나중**이 안전합니다.

UI 절차:

1. 카탈로그 항목(블루프린트)의 **커스텀 폼**부터 삭제/초기화 — Content & Policies → Content → 항목 → Custom Form 제거.
2. **블루프린트** 삭제 — Design → Cloud Templates(또는 Blueprints)에서 대상 3개 삭제:
   - `blueprint_vm` (또는 import 시 지정한 이름)
   - `blueprint_vm_storageclass_manual`
   - `blueprint_vra_cluster`
   블루프린트를 지우면 연결된 카탈로그 item 도 자동 정리됩니다.

REST 로 하고 싶다면(참고):

```bash
bp_remote_list                       # 현재 블루프린트 + id 확인
form_remote_delete <form-id>         # (폼이 form-service 쪽에 따로 남아있다면)
bp_remote_delete <blueprint-id>      # blueprint + catalog item 자동 정리
```

---

## Step 3 — UI 에서 삭제: 패키지(com.dk) + 액션

UI 절차:

1. vRO(Embedded Orchestrator) → Assets → **Packages** → `com.dk` 삭제.
   - 삭제 시 "패키지만 삭제 / 패키지+element 삭제" 옵션이 나오면, **깨끗한 재업로드가 목적이므로 element(액션)까지 삭제**를 선택.
2. element 가 남아있다면 Assets → **Actions** → 모듈 `com.vmk.dk` 의 액션 17개 삭제.

> ⚠ 모듈 **`com.vmk`** (ConfManager/TaskManager/Vcsa·Vra·NsxtManager 등)는 **건드리지 마세요.**
> 이 재업로드 대상은 **`com.vmk.dk`** 17개뿐입니다. (`com.vmk` 는 서버에 이미 있는 별개 자산)

현재 등록 상태 확인(REST):

```bash
vco_list_packages                    # com.dk 가 보이는지
vco_list_actions com.vmk.dk          # 삭제 후 0건이어야 함
```

---

## Step 4 — 패키지 import (액션 17개 복원)

```bash
vco_import_package packages/com.dk.package true
```

- 두 번째 인자 `true` = overwrite. `HTTP_STATUS=200` 이면 성공.
- 이 한 번의 import 가 **com.vmk.dk 액션 17개 전부를 올바른 runtime/output-type 으로 복원**합니다 (검증됨):
  - Python 3개 (`ChangePasswordHash`, `doubleBase64`, `validatePasswordMatch`) → **runtime `python:3.11`**
  - `{id,name}` 드롭다운용 10개 (`getVMClass`, `getStorageClass`, `getStorageClassOptional`, `getContentsLibrary`, `getKRVersion`, `getOS`, `getStroageClassManual`, `getStroageClassManualOptionals`, `getUbuntuVersion`, `getVMImage`) → **output-type `Array/Properties`**
  - `getProjectsNames`, `getNamespaces` → **output-type `Array/string`**
  - 나머지 string 4개(`getAdminUserByImage` 포함) + `dumpVcRoots`(`Any`, 내부 디버그용·어디서도 `$data` 로 참조 안 됨 → 무해)

> 패키지가 runtime/output-type 까지 복원하므로, **Step 4 만으로 "python 3.x 런타임"과 "출력 타입" 문제는 끝**입니다.
>
> ⚠ **반드시 패키지로만 import 하세요.** 아래 대체 경로는 타입/런타임을 망가뜨립니다:
> - `vco_import_all_js`, 인자 없는 `vco_import_action` → output-type 기본값이 **`Any`** → blueprint release 가 `VRO action not found` (400). (런타임도 `def handler` 없으면 미설정)
> - `vco_import_data_actions` 는 **blueprint `$data` 드롭다운 복구용**일 뿐 — `blueprints/` 만 스캔하므로
>   Python 액션 3개(`ChangePasswordHash`/`doubleBase64`/`validatePasswordMatch`, blueprint `$data` 에 안 나옴)를 **빠뜨립니다**. 패키지의 대체재가 아닙니다.

### 복원 검증 — 매니페스트와 대조

```bash
vco_list_actions com.vmk.dk          # NAME/VERSION/FQN 17행이 나오는지
jq -r '.[] | "\(.name)\t\(.outputType)\t\(.runtime)"' packages/actions-backup/com.vmk.dk/_manifest.json
```

- `vco_list_actions com.vmk.dk` 가 **17행**이면 코드 복원 OK.
- output-type 까지 점검하려면:
  ```bash
  vco_check_data_actions               # 각 $data 의 output-type 이 Any 가 아닌지 (전부 OK 여야 함)
  ```

---

## Step 5 — 블루프린트 import (★ 반드시 신규로)

**중요.** 기존 블루프린트의 `$data` 인덱스는 재게시(re-publish)해도 **갱신되지 않습니다.**
현재 액션을 반영하려면 **새로 생성된 블루프린트**여야 합니다. → Step 2 에서 지운 뒤, 여기서 fresh import.

세 블루프린트를 import 합니다 (release 는 Step 6 에서 폼과 함께):

```bash
bp_remote_import blueprints/vm/blueprint_vm.yaml
# → 성공 시 VCFA_BP_ID 가 셸에 export 됨 (다음 단계가 자동 사용)

bp_remote_import blueprints/vm/blueprint_vm_storageclass_manual.yaml
bp_remote_import blueprints/cluster/blueprint_vra_cluster.yaml
```

> ⚠ **fresh 게이트 (이 단계의 핵심).** `bp_remote_import` 는 같은 이름이 있으면 POST(create)가 아니라 **PUT(update)** 합니다.
> 게다가 이름 매칭은 **모든 project 횡단** — 다른 project 에 남은 동명 blueprint(미release DRAFT 포함)도 걸려서, 모르는 새
> **update** 되어 `$data` 인덱스가 stale 인 채로 남습니다(= '재게시해도 드롭다운 안 바뀜' 재발). `OK: blueprint updated` 라고 안심시키며 깨집니다.
>
> 두 가지 방법 중 하나를 쓰세요(둘 다 update 를 막아 fresh 보장):
> ```bash
> # 방법 A (권장·편함) — 동명(현재 project)을 자동 삭제하고 새로 생성:
> export VCFA_BP_RECREATE=1      # bp_remote_import 가 동명 삭제 후 POST(create). 다른 project 동명은 유지.
>
> # 방법 B (수동·보수적) — 직접 지우고, 남아 있으면 에러로 멈춤:
> bp_remote_list                 # vm / vm_storageclass_manual / vra_cluster 가 (어느 project 에도) 없어야 함
> #   남아 있으면: bp_remote_delete <id> 로 삭제
> export VCFA_BP_CREATE_ONLY=1   # 동명이 있으면 update 대신 에러로 멈춤(가짜 'updated' 방지)
> ```
> (`scripts/clean-deploy.sh` 는 **방법 A(`VCFA_BP_RECREATE=1`)** 를 자동 적용 — 기존 동명 blueprint 를 삭제·재생성하므로 UI 에서 미리 안 지워도 됩니다.)
>
> 한 개씩 처리하면 `VCFA_BP_ID` 가 항상 직전 것으로 갱신되니, **블루프린트 ↔ 폼 한 쌍씩 묶어서** Step 6 와 번갈아 진행하세요.

블루프린트 ↔ 폼 매핑:

| 블루프린트 | 짝 폼 |
| --- | --- |
| `blueprints/vm/blueprint_vm.yaml` | `forms/vm/custom_vm.yml` |
| `blueprints/vm/blueprint_vm_storageclass_manual.yaml` | `forms/vm/custom_vm_storageclass_manual.yml` |
| `blueprints/cluster/blueprint_vra_cluster.yaml` | `forms/cluster/custom_cluster.yml` |

> `forms/archive/` 의 파일은 레거시 백업입니다. 운영에 쓰지 마세요.

---

## Step 6 — 커스텀 폼을 블루프린트에 set (★ release 前) → release

VCF Automation 9.x 카탈로그는 **블루프린트에 붙은 폼**을 사용합니다 (form-service 쪽 폼이 아님).
그래서 **`bp_set_form` 으로 블루프린트에 폼을 먼저 set 한 뒤 release** 해야 카탈로그가 그 폼을 가져갑니다.

가장 안전한 권장 흐름 — **한 쌍씩 import → set → release**:

```bash
# ── VM ──
bp_remote_import blueprints/vm/blueprint_vm.yaml
bp_set_form "$VCFA_BP_ID" forms/vm/custom_vm.yml
bp_remote_release                                 # VCFA_BP_ID 자동 사용, catalog item 자동 생성

# ── VM (storageclass manual) ──
bp_remote_import blueprints/vm/blueprint_vm_storageclass_manual.yaml
bp_set_form "$VCFA_BP_ID" forms/vm/custom_vm_storageclass_manual.yml
bp_remote_release

# ── Cluster ──
bp_remote_import blueprints/cluster/blueprint_vra_cluster.yaml
bp_set_form "$VCFA_BP_ID" forms/cluster/custom_cluster.yml
bp_remote_release
```

또는 한 줄 체이닝 헬퍼 `content_publish` (import → bp_set_form(release 前) → release 를 자동으로 순서대로 수행):

```bash
content_publish blueprints/vm/blueprint_vm.yaml                       forms/vm/custom_vm.yml
content_publish blueprints/vm/blueprint_vm_storageclass_manual.yaml   forms/vm/custom_vm_storageclass_manual.yml
content_publish blueprints/cluster/blueprint_vra_cluster.yaml         forms/cluster/custom_cluster.yml
```

> `content_publish` 내부 순서는 `[1/3] bp_remote_import` → `[2/3] bp_set_form (release 前)` → `[3/3] bp_remote_release`
> 로 고정돼 있어, "폼을 release 前에 블루프린트에 set" 규칙을 자동으로 지킵니다.

### signpostPosition 관련 주의 (폼 렌더링 버그)

- 이 빌드에서 **layout 레벨의 `signpostPosition`** 속성(폼 YAML `.layout.pages[].sections[].fields[]` 아래 한 줄,
  예: `signpostPosition: right-middle`)이 **카탈로그 드롭다운 렌더링을 깨뜨립니다**(무한로딩).
  툴팁 텍스트는 schema 의 `signpost:` / `description:` 키로 살아있으니 **그 둘은 유지**하고,
  layout 레벨의 `signpostPosition` 줄만 제거해야 합니다. (`signpostPosition` 과 schema 키 `signpost:` 는 다른 것)
- **현재 repo 의 폼 3개에는 `signpostPosition` 이 이미 제거되어 있습니다** (`grep -rn signpostPosition forms/` → 0건).
  그래서 repo 폼을 그대로 import 하면 안전합니다.
- ✅ `bp_set_form`(과 `form_remote_import`)은 이제 **전송 직전 `signpostPosition` 을 재귀적으로 제거**합니다
  (`jq walk(... del(.signpostPosition) ...)`, schema 의 `signpost:` 는 보존). stale 폼 파일이 들어와도 렌더링이 깨지지 않습니다.
- 그래도 **벨트+서스펜더**로 import 전 폼 파일에 남은 게 없는지 확인하는 걸 권장합니다:
  ```bash
  grep -rn 'signpostPosition' forms/vm/custom_vm.yml forms/vm/custom_vm_storageclass_manual.yml forms/cluster/custom_cluster.yml
  # → 아무 것도 안 나와야 정상 (현재 repo 폼 3개는 0건)
  ```

---

## Step 7 — 드롭다운 렌더링 검증

### 7-1. 블루프린트 data 엔드포인트 (백엔드 검증)

카탈로그 UI 를 열기 전에, 블루프린트의 `$data` 엔드포인트가 **`{id,name}` 리스트**를 주는지 curl 로 확인합니다.
`<bp-id>` 는 `bp_remote_list` 또는 import 시 export 된 `VCFA_BP_ID` 사용.

```bash
bp_remote_list     # 대상 블루프린트 id 확인

curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "https://${VCFA_FQDN}/blueprint/api/blueprints/<bp-id>/data/vro-actions/com.vmk.dk/getVMClass?apiVersion=2020-08-25" | jq .
```

기대 출력 — 다음처럼 `id`/`name` 쌍의 배열이면 정상(드롭다운 렌더링됨):

```json
[
  {"id":"custom-best-effort-large-4c-8g","name":"custom-best-effort-large-4c-8g"},
  {"id":"...","name":"..."}
]
```

- 빈 배열 `[]` 이면 → Step 0.5 (Host/vCenter/vAPI 등록) 또는 토큰 점검.
- 4xx/5xx 이면 → 블루프린트가 신규가 아니거나(Step 5) `$data` output-type 문제(`vco_check_data_actions`).
- 다른 필드도 같은 패턴으로 점검: `.../com.vmk.dk/getProjectsNames`, `.../getStorageClass`, `.../getVMImage`.

### 7-2. 카탈로그 요청 폼 (UI 최종 확인)

1. Service Broker / 카탈로그 → 해당 항목 **Request**.
2. Project / Namespace / VM Class / VM Image / Storage Class 드롭다운이 **무한로딩 없이 값으로 채워지는지** 확인.
3. 무한로딩이면:
   - 데이터는 200 인데 모든 드롭다운만 안 그려짐 → 브라우저 렌더링 이슈 가능(F12 Console 의 빨간 JS 에러 확인, 다른 브라우저 시도).
   - 특정 폼 필드만 무한로딩 → 그 폼에 `signpostPosition` 이 남아있는지 재확인(Step 6).
   - 직접 RUN 은 되는데 카탈로그만 빈값 → VCFA:Host 가 `Per User Session` (Shared Session 으로 재등록, Step 0.5).

---

## 왜 이번엔 안 깨지나 — 과거 실패 ↔ 방지 단계 매핑

| 과거 실패 | 원인 | 이 런북에서 막는 단계 |
| --- | --- | --- |
| Python 액션이 3.10 등 잘못된 런타임 | 개별 import 시 런타임 오기입 | **Step 4** — 패키지가 `python:3.11` 까지 복원 |
| 드롭다운이 `{label,value}` 라 무한로딩 | output-type 이 틀림 | **Step 4** — 패키지가 `Array/Properties`/`Array/string`({id,name}) output-type 복원, `vco_check_data_actions` 로 확인 |
| `signpostPosition` 때문에 드롭다운 무한로딩 | layout 레벨 속성이 렌더링 깨뜨림 | **Step 6** — repo 폼엔 이미 제거됨 + import 전 `grep` 확인 |
| Host/vCenter/vAPI 미등록으로 빈값/`getVMImage` 실패 | 패키지에 없는 인벤토리 등록 누락 | **Step 0.5** — `vcfa_register_host`/`_vcenter`/`_vapi` |
| 재게시해도 드롭다운 안 바뀜 | 기존 블루프린트 `$data` 인덱스가 갱신 안 됨 | **Step 5** — 반드시 **신규** 블루프린트 import |
| 폼을 form-service 에 올렸는데 카탈로그가 안 씀 | 9.x 는 블루프린트에 붙은 폼만 사용 | **Step 6** — `bp_set_form` 으로 **블루프린트에** set, **release 前** |

---

## 참고 — 관련 문서

- 일상 배포/수정: [deploy.md](deploy.md)
- 오프라인 초기 셋업: [offline-setup.md](offline-setup.md)
- 작업 기록: [../worklog.md](../worklog.md)
