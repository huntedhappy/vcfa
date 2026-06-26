# vcfa

## 빠른 시작
```bash
cd /var/tmp
git clone git@github.com:huntedhappy/vcfa.git ${PWD}/vcfa && cd vcfa
cp .env.example        .env          # provider(System) 모드용
cp .env.tenant.example .env.tenant   # tenant 모드용 (복사만으로 tenant 모드 — VCFA_TENANT_ORG 이미 설정됨)
```

> ⚠️ **두 템플릿은 로그인 모드가 다릅니다.**
> - `.env` (← `.env.example`): provider 기본. `VCFA_USER=admin@system`, `VCFA_TENANT_ORG` 주석. → System 작업만. blueprint/form/**project-service/catalog** API 는 **403**.
> - `.env.tenant` (← `.env.tenant.example`): tenant. `VCFA_TENANT_ORG` 설정됨 → tenant 로그인. **project 멤버 user** 토큰만 위 API 가 200.
>
> 복사 후 `.env.tenant` 에서 **`VCFA_USER` / `VCFA_PASS` 만** 본인 tenant 계정으로 바꾸면 됩니다.
> (`VCFA_TENANT_ORG` 가 비어 있으면 provider 모드로 로그인되어 `project-service ... HTTP=403` 이 납니다.)

---

## 한 번에 — 배포(올리기) / 받기(받아오기)

레포 ↔ VCFA 를 한 줄로. 둘 다 `.env.tenant` 만 맞으면 동작 (인자 생략 시 `.env.tenant` 기본).

### 올리기 (repo → VCFA) : `clean-deploy.sh`
```bash
bash scripts/clean-deploy.sh .env.tenant
```
등록(Host/vCenter/vAPI, 이미 있으면 자동 생략) → 패키지 import → **동명 blueprint 삭제 후 fresh 생성** + 폼(signpostPosition 자동 제거) → 검증.
- UI 에서 blueprint 를 미리 안 지워도 됨 (recreate 가 삭제+재생성). 끝나면 카탈로그 Request 폼에서 드롭다운 확인.
- 전제(`.env.tenant`): 로그인 4개 + `VCFA_HOST_API_TOKEN`(UI 발급 *지속* 토큰) + `VC_HOST`/`VC_USER`/`VC_PASS`.

### 받기 (VCFA → repo) : `clean-export.sh`
```bash
bash scripts/clean-export.sh .env.tenant
git diff -- packages actions blueprints forms     # 바뀐 내용 확인
git add -A && git commit && git push origin main
```
로컬 관리파일 삭제 → 라이브에서 package/actions/blueprints/forms 를 받아 각 폴더에 저장 (폼은 *블루프린트에 붙은 것*에서, form-service 아님).
- ⚠️ **라이브 현재 상태 그대로** 받아 로컬을 덮어씀 → 받기 전 VCFA 가 "최종 상태" 인지 확인.
- 전제(`.env.tenant`): 로그인 4개만 (`VC_*`/토큰 불필요 — 등록은 export 에 안 씀).
- 잘못 받으면 복구: `git checkout -- packages actions blueprints forms`
- 매핑에 없는 라이브 blueprint 는 `blueprints/exported`·`forms/exported` 로 받음 → 필요 시 `scripts/clean-export.sh` 의 `MAP` 에 추가.

> 흐름: `repo ──(clean-deploy)──▶ VCFA ──(UI 테스트·수정)──▶ ──(clean-export)──▶ repo ──(commit/push)`
> 상세 단계별 수동 절차는 [docs/runbooks/clean-reupload.md](docs/runbooks/clean-reupload.md) 참고.

---

# 1. System 모드
```bash
source scripts/session.sh
```

```bash
# ORG (System 모드 전용 — 모든 org 가시성)
vcfa_list_orgs
vcfa_select_org # org 선택하면 자동으로 .env 파일에 저장
vcfa_org_quota # org에 limit 할당된 쿼터 확인
VCFA_ORG_NAME=Org1 vcfa_org_quota # 임시로 다른 org 확인

# vRO 액션  ※ tenant 모드에서도 동일하게 작동 — actions/packages 는 환경 전역 자산
vco_list_actions # Embeded vRo 전체 Actions 확인
vco_list_actions com.vmk.dk # Embeded com.vmk.dk에 Actions 화인
# 단일 import — vco_import_action <FILE> <MODULE> [OUTPUT_TYPE=Any] [INPUT_PARAMS_JSON=[]]
vco_import_action actions/com.vmk.dk/getOS.js com.vmk.dk                          # 기본 (Any, 입력 없음)
vco_import_action actions/com.vmk.dk/getOS.js com.vmk.dk Array/Properties         # 반환 타입 지정
vco_import_action actions/com.vmk.dk/getNamespaces.js com.vmk.dk Array/string \
  '[{"name":"ProjectName","type":"string","description":""}]'                     # 입력 파라미터 지정

# 디렉터리 일괄 import (모든 *.js — 기본 output-type=Any, inputs=[])
vco_import_all_js actions/com.vmk.dk com.vmk.dk
# ※ output-type / input 이 다른 액션은 위 vco_import_action 으로 한 번 더 호출 → 덮어쓰기

# ★ blueprint 의 $data 드롭다운/계산값 소스로 쓰는 액션은 반드시 "구체 output-type" 으로 import.
#   output-type=Any 면 Cloud Assembly 가 인덱싱 안 함 → release 가 "VRO action ... not found" (HTTP 400).
#   아래 헬퍼가 blueprint 들을 스캔해, 각 $data 액션을 파일 헤더의 'Return type:' + blueprint 쿼리의 입력으로
#   자동 import 함 (헤더 기반·멱등). 새 환경 bring-up 시 한 줄이면 끝.
vco_import_data_actions                 # blueprints/ 의 모든 $data 액션을 올바른 타입/입력으로 import
vco_check_data_actions                  # (preflight) 각 $data 액션이 vRO 에 존재 + output-type≠Any 인지 점검

# vRO 패키지
# ── 로컬 파일 검사 (offline, 서버 호출 없음) ──
pkg_list                          # packages/*.package 파일 목록 + element 수 + 서명 여부 + size
pkg_check                         # ZIP 무결성 + 필수 구조 (dunes-meta-inf / signatures / certificates) 검증
pkg_show packages/com.dk.package  # 메타데이터 (pkg-name, pkg-signer, version) + 내부 action element 목록

# ── vRO 서버 작업 (Bearer 토큰 사용) ──
vco_list_packages                                 # vRO 서버의 패키지 링크 목록
vco_package_details packages/com.dk.package       # 로컬 파일을 vRO 에 보내 import 미리보기 (dry-run)
vco_import_package  packages/com.dk.package       # 로컬 파일을 vRO 에 실제 import (overwrite=true)
vco_export_package  com.dk                        # vRO 의 패키지를 → packages/com.dk.package 다운로드
vco_package_sync_module com.dk com.vmk.dk         # 모듈의 모든 action 을 패키지에 동기화 (누락 element 자동 추가)
```
> 💡 **모듈에 새 action 추가 후 패키지에도 포함시키기** — `vco_import_action` 으로 모듈에 액션을 추가해도 `vco_export_package` 한 .package 에는 안 들어감. 다음 함수로 모듈의 모든 action 을 패키지에 sync:
>
> ```bash
> vco_package_sync_module com.dk com.vmk.dk    # com.vmk.dk 의 모든 액션을 com.dk 패키지에 포함
> vco_export_package      com.dk               # 갱신된 .package 다운로드 (모든 element 포함)
> ```
>
> 내부 동작: 기존 서명된 .package 를 base 로 새 element 만 unsigned 로 추가한 ZIP 을 vRO 에 import. vRO 가 partial-signed 패키지를 받아들이는 동작 활용 (검증 완료 2026-05-24).

---

# 2. Tenant 모드 
```bash
source scripts/session.sh .env.tenant
```

```bash
# 선택 (첫 1회만 — .env.tenant 에 자동 저장)
vcfa_list_orgs       ; vcfa_select_org
vcfa_list_projects   ; vcfa_select_project
vcfa_list_namespaces ; vcfa_select_namespace

# 로컬 파일 검증
bp_list ; bp_check
bp_show blueprints/vm/blueprint_vm.yaml
form_list ; form_check
form_show forms/vm/custom_vm.yml
content_pairs

# vRO 액션 + 인벤토리 호스트 (최초 1회 — 드롭다운 동작 전제)
vco_import_data_actions                                            # com.vmk.dk $data 액션 import (output-type 헤더 기반 자동)
vcfa_register_host                                                # VCFA:Host. VCFA_HOST_API_TOKEN(UI 발급) 있으면 Shared Session → 카탈로그 폼 드롭다운 동작
vcfa_register_vcenter ; vcfa_register_vapi                        # (선택) getStorageClass / getVMImage 데이터 소스

# Blueprint + Form import (권장)
content_publish_all                                                # 모든 운영 파일 일괄 (release 전 $data 액션 preflight 자동)
content_publish_all --include-archive                              # archive 포함
content_publish_all --cleanup-on-fail                              # release/form 실패 시 만들어진 DRAFT 자동 삭제
content_publish_all --skip-preflight                               # $data 액션 preflight 건너뛰기
content_publish blueprints/vm/blueprint_vm.yaml forms/vm/custom_vm.yml   # 한 쌍만
# ℹ️ release 가 "VRO action ... not found" (400) 면 → $data 액션이 output-type=Any. 'vco_import_data_actions' 로 고치고 재시도.

# Blueprint REST (단계별)
bp_remote_list
bp_remote_import blueprints/vm/blueprint_vm.yaml
bp_remote_release
bp_remote_release <bp-id> v1.0.0 "first release"
bp_remote_delete <bp-id>

# Blueprint Export — 서버 → 로컬 파일
bp_remote_export <bp-id>                          # 기본: blueprints/exported/blueprint_<name>.yaml
bp_remote_export <bp-id> blueprints/vm/           # sub-dir 지정 → blueprints/vm/blueprint_<name>.yaml
bp_remote_export <bp-id> /tmp/my.yaml             # 명시 파일 경로
bp_select_export                                  # 대화식 — 목록 → 번호 선택 → 다운로드
bp_select_export blueprints/vm                    # 저장 위치 지정

# Catalog + Form REST
catalog_remote_list
form_remote_import forms/vm/custom_vm.yml         # → VCFA_FORM_ID 자동 export
form_remote_import forms/vm/custom_vm.yml <catalog-item-id>
form_remote_delete <form-id>

# Form Export — 서버 → 로컬 파일
form_remote_export <form-id>                      # 기본: forms/exported/custom_<form-id>.yml
form_remote_export <form-id> forms/vm/            # sub-dir
form_remote_export <form-id> forms/vm/ vm         # 파일명에 쓸 이름 → forms/vm/custom_vm.yml
form_select_export                                # 대화식 — catalog item 목록 표시 + form-id 입력
# ℹ️ form 서버에 list endpoint 없음 → form-id 직접 알아야 함 (form_remote_import 직후 VCFA_FORM_ID 사용 가능)

# Namespace 한도 (UI 동기화)
vcfa_list_namespaces ; vcfa_select_namespace

vcfa_namespace_show_limit_cci
vcfa_namespace_set_limit_cci cpu_limit_ghz=80 mem_limit_gib=80
vcfa_namespace_set_limit_cci cpu_limit_thz=1
vcfa_namespace_set_limit_cci cpu_rsv_ghz=10 mem_rsv_gib=8
vcfa_namespace_set_limit_cci cpu_limit_mhz=100000 mem_limit_mib=102400
vcfa_namespace_set_limit_cci cpu_limit_ghz=80 mem_limit_gib=80 cpu_rsv_ghz=10 mem_rsv_gib=8

vcfa_namespace_set_storage_limit_cci storage_limit_tib=1
vcfa_namespace_set_storage_limit_cci storage_limit_gib=2500
vcfa_namespace_set_storage_limit_cci storage_limit_mib=2560000
```

### 단위 환산표 (CCI 한도 KEY)
| KEY | 단위 |
|---|---|
| `cpu_*_mhz` / `cpu_*_ghz` / `cpu_*_thz` | MHz / GHz / THz |
| `mem_*_mib` / `mem_*_gib` / `mem_*_tib` | MiB / GiB / TiB |
| `storage_limit_mib` / `storage_limit_gib` / `storage_limit_tib` | MiB / GiB / TiB |


## 기타
### OIDC Redirect URL

```bash
ORG_UUID="${VCFA_ORG_ID##*:}"
echo "ORG_UUID=${ORG_UUID}"

curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/*+json;version=10.0.0.0-alpha" \
  "https://$VCFA_FQDN/api/admin/org/${ORG_UUID}/settings/oauth" \
  | jq '.orgRedirectUri'
```