# vcfa

## 빠른 시작
```bash
cd /var/tmp
git clone git@github.com:huntedhappy/vcfa.git ${PWD}/vcfa && cd vcfa
cp .env.example .env             # provider 자격증명
cp .env.example .env.tenant      # tenant 자격증명 + export VCFA_TENANT_ORG="ProviderConsumptionOrg"
```

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

# Blueprint + Form import (권장)
content_publish_all                                                # 모든 운영 파일 일괄
content_publish_all --include-archive                              # archive 포함
content_publish_all --cleanup-on-fail                              # release/form 실패 시 만들어진 DRAFT 자동 삭제
content_publish blueprints/vm/blueprint_vm.yaml forms/vm/custom_vm.yml   # 한 쌍만

# Blueprint REST (단계별)
bp_remote_list
bp_remote_import blueprints/vm/blueprint_vm.yaml
bp_remote_release
bp_remote_release <bp-id> v1.0.0 "first release"
bp_remote_export <bp-id>
bp_remote_export <bp-id> /tmp/my.yaml
bp_remote_delete <bp-id>

# Catalog + Form REST
catalog_remote_list
form_remote_import forms/vm/custom_vm.yml
form_remote_import forms/vm/custom_vm.yml <catalog-item-id>
form_remote_delete <form-id>

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
