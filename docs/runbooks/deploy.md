# Runbook — 어디를 수정하고 어떻게 배포까지 가나

> **이 문서는 "처음 보는 사람도 따라 할 수 있게"가 목표.** 검증된 사실(파일·입력명·`$data` 경로)은 단정하고, 외부 UI 동작·환경값은 "확인 필요"로 표기합니다.

전체 흐름:

```
[수정] blueprints/forms/actions
   │
   ▼
[Import] vRO 액션 → Cloud Assembly 블루프린트 → Service Broker 폼
   │
   ▼
[배포] Service Broker 카탈로그 요청
```

---

## ⚡ 빠른 실행 — 스크립트 자동화 (라이브 검증 2026-06-25)

> `scripts/`의 헬퍼로 처음부터 끝까지 자동화한, **실제 검증된 절차**. 아래 수동 UI 절차(1장 이후)보다 이걸 우선하세요.
> 함수 정의: `scripts/vcfa-vro-package-lib.sh` / `scripts/vcfa-content-lib.sh`.

### 0) `.env.tenant` 준비 (최초 1회) — `.env.tenant.example` 참조

| 키 | 용도 |
| --- | --- |
| `VCFA_FQDN` `VCFA_USER` `VCFA_TENANT_ORG` `VCFA_PASS` `VCFA_API_VERSION` | 로그인 (tenant 모드) |
| **`VCFA_HOST_API_TOKEN`** | 카탈로그 폼 드롭다운 동작에 **필수**. VCFA 콘솔 UI 우상단 사용자메뉴 → **API Tokens → Generate** 로 발급(API로는 거부됨). |
| `VC_HOST` `VC_USER` `VC_PASS` | 밑단 vCenter — Storage Class / VM Image 소스용 |

### 1) 세션 로그인
```bash
source scripts/session.sh .env.tenant
```

### 2) vRO 액션 import (`com.vmk.dk`)
```bash
vco_import_data_actions          # JS $data 액션 — output-type/inputs 자동
# Python 3개 (runtime=python:3.10 자동감지):
vco_import_action actions/com.vmk.dk/doubleBase64.js          com.vmk.dk string '[{"name":"TrustCA","type":"string","description":""}]'
vco_import_action actions/com.vmk.dk/ChangePasswordHash.js    com.vmk.dk string '[{"name":"passwd","type":"string","description":""}]'
vco_import_action actions/com.vmk.dk/validatePasswordMatch.js com.vmk.dk string '[{"name":"pw1","type":"string","description":""},{"name":"pw2","type":"string","description":""}]'
```
> `com.vmk` 5개(ConfManager/TaskManager/Vcsa·Vra·NsxtManager)는 **서버에 이미 있음 → 재import 금지**(input 파라미터 손상). VraManager 등은 9.x All-Apps 비호환 레거시(아래 4장 참조).

### 3) 인벤토리 호스트 등록 (드롭다운 데이터 소스)
```bash
vcfa_register_host        # VCFA:Host (projects/namespaces). VCFA_HOST_API_TOKEN 있으면 Shared Session 자동(카탈로그 폼 동작), 기존 호스트면 Update.
# vcfa_register_vcenter   # (선택/레거시) getStorageClass 도 2026-06-26 CCI 전환 → 어떤 $data 액션도 vCenter 미사용. 진단(dumpVcRoots)용만.
# vcfa_register_vapi      # (선택/레거시) 2026-06-26 이후 어떤 $data 액션도 미사용(전부 CCI). 수동 VAPIManager 용도만.
```

### 4) 검증
```bash
vco_run_action com.vmk.dk/getProjectsNames                        # → ["vcfa2","default-project",...] (빈값이면 호스트/토큰 문제)
vco_run_action com.vmk.dk/getNamespaces ProjectName=default-project
vco_check_data_actions                                            # 각 $data 의 output-type 점검
```

### 5) 블루프린트 / 폼 (REST 자동화)
```bash
catalog_remote_list                                              # 현재 카탈로그 item
content_publish blueprints/vm/blueprint_vm.yaml forms/vm/custom_vm.yml   # import→release→form 체이닝
# 일괄: content_publish_all
```

### 함정 / 트러블슈팅 (검증됨)

| 증상 | 원인 / 조치 |
| --- | --- |
| **카탈로그 폼이 전부 무한로딩** | VCFA:Host 가 `Per User Session` 이거나 API 토큰 만료. `VCFA_HOST_API_TOKEN` 갱신 → `vcfa_register_host` 재실행(Shared Session). |
| 직접 RUN은 되는데 카탈로그만 빈값 | 위와 동일 (카탈로그는 서비스 컨텍스트라 per-user 세션 없음 → Shared Session 필요). |
| VM Image 드롭다운 비어있음 | `getVMImage` 는 VCFA:Host 의 CCI 프록시로 `clustervirtualmachineimages` 를 조회(입력 없음). 빈값이면 VCFA:Host 등록/토큰 또는 Supervisor 에 published VM 이미지 유무 확인. (더 이상 vAPI·`vra-image` 라이브러리 불필요) |
| Storage Class 가 `k8s` 만 (옛 버그) | RESOLVED 2026-06-26 — getStorageClass(Optional) 을 CCI `status.storageClasses` 로 전환(실제 클래스명 예 `obcluster-vsan-storage-policy`). vCenter PBM 경로·하드코딩 `k8s` 제거. |
| `$data` 액션 throw | 액션은 throw 금지 → `[]` 반환해야 폼이 안 깨짐(이미 적용됨). |
| **드롭다운 무한로딩(특정 필드: projects/namespace 등)** | 그 `$data` 액션이 `Array/string`({id,name}) → 카탈로그가 UI에 줄 때 value/label 없어 못 그림. **`Array/Properties` {label,value}** 로 반환하도록 액션 수정(`new Properties(); put("label",x); put("value",x)`). |
| **데이터는 200으로 오는데 모든 드롭다운 무한로딩** | 백엔드/형식 다 정상(pod 로그·HAR이 200)이면 **브라우저 UI 렌더링** 문제. ① 다른 브라우저(Firefox/Edge)로 시도, ② F12 → **Console** 탭의 빨간 JS 에러 확인(Network/HAR·pod 로그엔 안 보임). 신버전 Chrome 호환 이슈면 Broadcom 케이스. |

---

## 0. 사전 준비

- 오프라인 환경이면 먼저 [offline-setup.md](offline-setup.md) 완료.
- vRO에 `VCFA:Host`가 1개 이상 등록되어 있어야 함 — [actions/com.vmk.dk/getProjectsNames.js](../../actions/com.vmk.dk/getProjectsNames.js)가 `Server.findAllForType("VCFA:Host", null)`로 호스트를 찾아 프로젝트를 조회합니다.
- vRO의 VRA 호스트 별칭 기본값은 `VMK` — [actions/com.vmk/VraManager.js](../../actions/com.vmk/VraManager.js)의 `_client` 폴백 참조. 다른 이름이면 호출 시 `manager` 변수를 명시.

---

## 1. 어디를 수정해야 하나

### 1-1. 환경값(가장 자주 바뀌는 곳)

[blueprints/vm/blueprint_vm.yaml](../../blueprints/vm/blueprint_vm.yaml)의 `inputs:` 기본값:

| input | 현재 기본값 | 의미 |
| --- | --- | --- |
| `hostname` | `webvm` | 게스트 hostname + 리소스 이름 prefix |
| `domainname` | `dtvcf.lab` | 도메인명 |
| `vmclass` | `custom-best-effort-large-4c-8g` | VM Class (vRO `getVMClass`가 반환하는 값 중 하나) |
| `vmCount` | `2` (min 1, max 10) | 배포 개수 |
| `osDiskSize` | `40Gi` | OS 디스크(확장 시) |
| (`image`/`storageclass`/`projects`/`namespace`/`adminUser`) | (런타임 동적) | vRO 액션이 옵션 목록 제공 |

[blueprints/cluster/blueprint_vra_cluster.yaml](../../blueprints/cluster/blueprint_vra_cluster.yaml)에서 자주 보는 곳:

| input | 기본값 | 의미 |
| --- | --- | --- |
| `vmclass_con` / `vmclass_worker` / `vmclass_worker2` | `custom-best-effort-large-4c-8g` | 마스터/워커 VM Class |
| `master_count` | `1` | 마스터 노드 수 |
| `worker_count` | `2` | 워커 NodePool 1 노드 수 |
| `default_disk_size` / `master_disk_size` / `worker_disk_size` | `100` / `100` / `200` (GiB) | 디스크 크기 |
| `enable_second_nodepool` | `false` | 워커 NodePool 2 활성화 |

### 1-2. vRO 액션 동작

블루프린트의 드롭다운/기본값이 이상하다면 짝이 되는 액션을 점검합니다:

| 입력 항목 | 호출 액션 |
| --- | --- |
| Project | [actions/com.vmk.dk/getProjectsNames.js](../../actions/com.vmk.dk/getProjectsNames.js) |
| Namespace | [actions/com.vmk.dk/getNameSpaces.js](../../actions/com.vmk.dk/getNameSpaces.js) |
| VM Class | [actions/com.vmk.dk/getVMClass.js](../../actions/com.vmk.dk/getVMClass.js) |
| VM Image | [actions/com.vmk.dk/getVMImage.js](../../actions/com.vmk.dk/getVMImage.js) (CCI `clustervirtualmachineimages`, 입력 없음) |
| Storage Class | [actions/com.vmk.dk/getStorageClass.js](../../actions/com.vmk.dk/getStorageClass.js) |
| OS Admin User | [actions/com.vmk.dk/getAdminUserByImage.js](../../actions/com.vmk.dk/getAdminUserByImage.js) |

### 1-3. 폼 레이아웃

UI 탭/순서/필드 표시 정책은 [forms/vm/custom_vm.yml](../../forms/vm/custom_vm.yml) (또는 짝이 되는 폼)에서 수정.

---

## 2. Import (vRO → Cloud Assembly → Service Broker)

### 2-1. vRO에 액션 가져오기

방법 A — **패키지 import (권장)**

1. vRO Client → *Assets → Packages → Import*
2. [packages/com.dk.package](../../packages/com.dk.package) 업로드
3. 서명/인증서 검증 통과 확인

방법 B — **개별 스크립트 등록**

1. *Assets → Actions* 에서 모듈 `com.vmk`, `com.vmk.dk`을 만든 뒤
2. [actions/com.vmk/](../../actions/com.vmk/) 와 [actions/com.vmk.dk/](../../actions/com.vmk.dk/) 의 각 `.js`를 동일 이름으로 생성·붙여넣기
3. 입력 파라미터/반환 타입을 스크립트 첫 주석(예: `// Inputs: 없음`, `// Return: Array/string`)에 맞게 설정

> Python 액션( [actions/com.vmk.dk/ChangePasswordHash.js](../../actions/com.vmk.dk/ChangePasswordHash.js) )은 실체가 Python 코드이므로 vRO에서 **언어를 Python으로** 선택해 등록.

### 2-2. Cloud Assembly에 블루프린트 가져오기

1. Cloud Assembly → *Design → Cloud Templates* → *New from* 로 [blueprints/vm/blueprint_vm.yaml](../../blueprints/vm/blueprint_vm.yaml) 내용 붙여넣기 (또는 Git Integration이 연결되어 있으면 해당 경로 선택)
2. 좌측 미리보기에서 input 드롭다운이 채워지는지 확인 — 채워지지 않으면 vRO 호스트/액션 모듈 경로 점검
3. 클러스터 블루프린트도 [blueprints/cluster/blueprint_vra_cluster.yaml](../../blueprints/cluster/blueprint_vra_cluster.yaml) 동일 방식

### 2-3. Service Broker에 폼 적용

1. 위 블루프린트를 Service Broker *Content Sources*로 가져온 뒤 카탈로그 항목 게시
2. *Content & Policies → Content* 에서 해당 항목 선택 → *Custom Form*
3. **짝이 맞는 폼**을 import:

| 블루프린트 | 짝 폼 |
| --- | --- |
| [blueprints/vm/blueprint_vm.yaml](../../blueprints/vm/blueprint_vm.yaml) | [forms/vm/custom_vm.yml](../../forms/vm/custom_vm.yml) |
| [blueprints/vm/blueprint_vm_storageclass_manual.yaml](../../blueprints/vm/blueprint_vm_storageclass_manual.yaml) | [forms/vm/custom_vm_storageclass_manual.yml](../../forms/vm/custom_vm_storageclass_manual.yml) |
| [blueprints/cluster/blueprint_vra_cluster.yaml](../../blueprints/cluster/blueprint_vra_cluster.yaml) | [forms/cluster/custom_cluster.yml](../../forms/cluster/custom_cluster.yml) |

> [forms/archive/](../../forms/archive/) 안의 폼은 **이전 버전 백업**입니다. 운영에 적용하지 마세요. 같은 폴더의 `custom_vra_cluster.yml`은 `custom_cluster.yml`과 동일 내용([tech-debt.md](../tech-debt.md) 참조).

---

## 3. 배포 (실행)

1. Service Broker → *Catalog* 에서 해당 항목 *Request*
2. 입력값 채우기 — Project / Namespace / Image 등 동적 드롭다운이 정상 노출되는지 확인
3. SSH Public Key·OS Password 입력 (비밀번호는 `encrypted: true, writeOnly: true`로 보호됨 — [security.md](../security.md))
4. *Submit* 후 *Deployments* 탭에서 진행 상태 확인

---

## 4. 트러블슈팅 (확인된 항목만)

| 증상 | 우선 점검 |
| --- | --- |
| 드롭다운이 비어 있음 | vRO에 `VCFA:Host` 등록 여부 + 액션이 모듈 `com.vmk.dk`로 들어가 있는지 |
| `VraManager()` 호출 실패 | [actions/com.vmk/VraManager.js](../../actions/com.vmk/VraManager.js) 의 `manager` 변수(기본 `"VMK"`)와 실제 vRO `vra-onprem` 호스트명 일치 여부 |
| 폼이 블루프린트 input과 어긋남 | 짝이 맞는 폼을 import했는지 (위 매핑표) |
| Storage Class가 "수동 입력"으로 떠야 함 | manual 변형 블루프린트/폼([blueprints/vm/blueprint_vm_storageclass_manual.yaml](../../blueprints/vm/blueprint_vm_storageclass_manual.yaml)) 사용 |

---

## 5. 변경 후 권장 순서 (PDCA)

1. **Plan** — 이 문서와 [worklog.md](../worklog.md)를 먼저 읽어 중복 작업 방지
2. **Do** — 최소 단위로 수정 (한 블루프린트 / 한 액션)
3. **Check** — Cloud Assembly 미리보기 → Service Broker 폼 미리보기 → 테스트 프로젝트에 배포 1회
4. **Act** — [worklog.md](../worklog.md)에 한 엔트리 append (수정 파일·검증 결과·미완성 항목)

---

## 6. VCFA REST API 인증 — 공통 토큰 발급

REST/curl로 자산을 업로드(blueprint·form·package)할 때 모든 호출이 공유하는 인증 절차. 각 폴더의 README에서 이 절을 참조합니다.

> ⚠ 아래 경로는 **vRA 8.x 표준 + VCFA 9에서 보편적으로 유효한 패턴**입니다. base URL prefix(예: `https://<vcfa>` 자체로 끝날지, 게이트웨이를 거칠지)는 환경마다 다르므로 **UI에서 한 번 로그인할 때 브라우저 DevTools → Network 탭으로 캡처해 확정**한 뒤 채우는 것을 권장.

### 6-1. 환경값 (시크릿은 env로만)

```bash
export VCFA_URL="https://vcfa.example.local"     # base URL
export VCFA_USER="serviceadministrator"
export VCFA_PASSWORD="${VCFA_PASSWORD:?env 비어 있음}"   # 절대 파일/git 금지
export VCFA_DOMAIN="System"                       # 또는 사용자 domain
export INSECURE=0                                 # 1이면 curl -k (운영 권장 안 함)
CURL_K=(); [ "$INSECURE" = "1" ] && CURL_K=(-k)
```

### 6-2. 두 단계 토큰 (refresh → access)

```bash
# (1) refresh token 발급
REFRESH_TOKEN=$(curl "${CURL_K[@]}" -fsSL -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${VCFA_USER}\",\"password\":\"${VCFA_PASSWORD}\",\"domain\":\"${VCFA_DOMAIN}\"}" \
  "${VCFA_URL}/csp/gateway/am/api/login?access_token" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["refresh_token"])')

# (2) access token(bearer) 교환
export VCFA_TOKEN=$(curl "${CURL_K[@]}" -fsSL -X POST \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"${REFRESH_TOKEN}\"}" \
  "${VCFA_URL}/iaas/api/login" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')

echo "token length: ${#VCFA_TOKEN}"   # 길이만 확인, 값 출력 금지
```

### 6-3. 이후 호출 헤더

```bash
AUTH=( -H "Authorization: Bearer ${VCFA_TOKEN}" -H "Accept: application/json" )
# 사용 예: curl "${CURL_K[@]}" -fsSL "${AUTH[@]}" "${VCFA_URL}/iaas/api/projects"
```

### 6-4. 환경에서 검증해야 할 부분

UI 로그인 1회로 캡처해 확정:

- `/csp/gateway/am/api/login` 의 정확한 query/body 형태
- `/iaas/api/login` 의 응답 JSON 키 이름 (`token` 인지 다른 이름인지)
- token 만료 시간 / 재발급 정책
- VCFA가 게이트웨이를 따로 두는지 (예: `https://api.<domain>` 으로 분리되어 있는지)

캡처값과 위 6-2의 path/payload가 다르면 그쪽이 정답 — 본 문서 값을 환경값으로 교체.
