source scripts/session.sh .env  

# TOKEN 확인
export BASIC_AUTH=$(printf "%s:%s" "$VCFA_USER" "$VCFA_PASS" | base64 -w0)

export TOKEN=$(
  curl -sk -i -X POST "https://${VCFA_FQDN}/cloudapi/1.0.0/sessions/provider" \
    -H "Accept: application/json;version=9.1.0" \
    -H "Content-Type: application/json;version=9.1.0" \
    -H "Authorization: Basic ${BASIC_AUTH}" \
  | awk -F': ' 'tolower($1)=="x-vmware-vcloud-access-token" {print $2}' \
  | tr -d '\r'
)

echo "TOKEN=${TOKEN}"

## ORG List 확인
curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/1.0.0/orgs?page=1&pageSize=128" \ |
 jq -r '
      ["NAME", "DISPLAY_NAME", "UUID"],
      (.values[]? | [
        .name,
        .displayName,
        (.id | sub("^urn:vcloud:org:"; ""))
      ])
      | @tsv
    ' \
  | column -t -s $'\t'

## ORG Quota 확인
curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters?page=1&pageSize=128" \
  | tee /tmp/vcfa-vdcs.json | jq .

## VCF Operations Orchestrator Package List 확인
curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  "${VCO_API_BASE}/packages" \
  | jq -r '
      ["REL", "TYPE", "HREF"],
      (.link[]? | [
        .rel,
        .type,
        .href
      ])
      | @tsv
    ' \
  | column -t -s $'\t'

## 업로드할 패키지 상세 확인
curl -sk -X POST \
  "${VCO_API_BASE}/packages/import-details" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  -F "file=@${PACKAGE_FILE}" \
  | jq .


## 패키지 Import
curl -sk -X POST \
  "${VCO_API_BASE}/packages?overwrite=true&importConfigurationAttributeValues=false&tagImportMode=ImportButPreserveExistingValue&importConfigSecureStringAttributeValues=false" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  -F "file=@${PACKAGE_FILE}" \
  -w "\nHTTP_STATUS=%{http_code}\n"

## TOKEN 유효성 검증 (만료 여부)
curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/1.0.0/sessions/current" \
  | jq '{user, org: .org.name, location, expirationDate: .expirationDate}'

## 선택된 ORG 의 VDC만 (Quota 필터)
# VCFA_ORG_ID 가 vcfa_select_org 로 export 되어 있다고 가정
curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters?page=1&pageSize=128" \
  | jq --arg id "${VCFA_ORG_ID}" '
      ["VDC", "ZONE", "CPU_LIMIT_MHz", "MEM_LIMIT_MiB", "STATUS"],
      (.values[]
        | select(.org.id == $id)
        | . as $vdc
        | .zoneResourceAllocation[]?
        | [$vdc.name, .zone.name,
           (.resourceAllocation.cpuLimitMHz // 0),
           (.resourceAllocation.memoryLimitMiB // 0),
           $vdc.status])
      | @tsv
    ' -r \
  | column -t -s $'\t'

## 선택된 ORG 의 Namespace 목록
# 1) ORG 의 VDC ID/Name 추출
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters?page=1&pageSize=128" \
  | jq -r --arg id "${VCFA_ORG_ID}" '.values[] | select(.org.id == $id) | "\(.id)\t\(.name)"'
# → VDC_ID 를 골라 다음 호출

# 2) 그 VDC 의 namespace 목록
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters/${VDC_ID}/namespaces?page=1&pageSize=128" \
  | jq -r '
      ["NAME", "STATUS", "CPU_USED/LIMIT", "MEM_USED/LIMIT", "ID"],
      (.values[]
        | . as $ns
        | (.zonalResourceAllocation[0].resourceAllocation // {}) as $r
        | [$ns.name, $ns.status,
           "\($r.cpuUsedMHz // 0)/\($r.cpuLimitMHz // 0)",
           "\($r.memoryUsedMiB // 0)/\($r.memoryLimitMiB // 0)",
           $ns.id])
      | @tsv
    ' \
  | column -t -s $'\t'

## Namespace 상세 (top-level path 로 ID 직접) ★ 단일 GET/PUT/DELETE 는 top-level path
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${NS_ID}" \
  | jq .
# 비고: 목록(LIST)은 /virtualDatacenters/{vdc}/namespaces, 단일 객체는 top-level /namespaces/{id}.
#       OPTIONS 응답: allow: HEAD,DELETE,GET,OPTIONS,PUT (PATCH 없음 → GET-modify-PUT 패턴)

## Namespace 리소스 limit/사용량만 (보기 좋게)
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${NS_ID}" \
  | jq '{ns: .name, status,
          zones: [.zonalResourceAllocation[] | {
            zone: .zone.name,
            cpuLimitMHz: .resourceAllocation.cpuLimitMHz,
            cpuReservationMHz: .resourceAllocation.cpuReservationMHz,
            memoryLimitMiB: .resourceAllocation.memoryLimitMiB,
            memoryReservationMiB: .resourceAllocation.memoryReservationMiB,
            cpuUsedMHz: .resourceAllocation.cpuUsedMHz,
            memoryUsedMiB: .resourceAllocation.memoryUsedMiB
          }]}'

## Namespace 리소스 limit 수정 (GET → 수정 → PUT, 응답 202 비동기)
# 1) 현재 객체 GET
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json;version=9.1.0" \
  "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${NS_ID}" > /tmp/ns-cur.json

# 2) 모든 zone 의 resourceAllocation 수정
# API 기본단위: cpuLimitMHz (MHz), memoryLimitMiB (MiB).
# 친근 단위로 입력하려면 미리 환산:
#   GHz → MHz : N * 1000        ;  THz → MHz : N * 1000000
#   GiB → MiB : N * 1024        ;  TiB → MiB : N * 1048576  (= 1024*1024)
# 예: cpu 80 GHz = 80000 MHz, mem 80 GiB = 81920 MiB
jq --argjson cpu 80000 --argjson mem 81920 '
  .zonalResourceAllocation |= map(
    .resourceAllocation.cpuLimitMHz = $cpu
    | .resourceAllocation.memoryLimitMiB = $mem
  )' /tmp/ns-cur.json > /tmp/ns-new.json

# 3) PUT 으로 통째 replace
curl -sk -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json;version=9.1.0" \
  -H "Content-Type: application/json;version=9.1.0" \
  -d @/tmp/ns-new.json \
  "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${NS_ID}" \
  -w "\nHTTP_STATUS=%{http_code}\n"
# 202 Accepted (task 비동기)

## vRO Package Export (현재 vRO 의 패키지를 .package 파일로 내려받기)
curl -sk -L \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/zip,application/octet-stream,*/*" \
  "${VCO_API_BASE}/packages/com.dk?exportConfigurationAttributeValues=false&exportConfigSecureStringAttributeValues=false&exportVersionHistory=false&exportGlobalTags=false&exportAsZip=false" \
  -o packages/com.dk.package
ls -lh packages/com.dk.package
file packages/com.dk.package

## vRO Action List (모듈 prefix 필터)
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${VCO_API_BASE}/actions" \
  | jq -r '
      ["NAME", "VERSION", "FQN"],
      (.link[]?
        | .attributes | from_entries
        | select(.fqn | startswith("com.vmk.dk/"))
        | [.name, .version, .fqn])
      | @tsv
    ' \
  | column -t -s $'\t'

## vRO Action Detail (by module/name)
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${VCO_API_BASE}/actions/com.vmk.dk/getProjectsNames/" | jq .

## vRO Action Detail (by id)
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${VCO_API_BASE}/actions/${ACTION_ID}/" | jq .

## vRO Action Create (신규 — module/name 없을 때 POST)
# JSON body 작성 (script 본문은 jq --rawfile 로 안전 인코딩)
jq -n \
  --rawfile script actions/com.vmk.dk/getOS.js \
  '{name:"getOS", module:"com.vmk.dk", version:"1.0.0",
    "output-type":"Array/Properties", "input-parameters":[], script:$script}' \
  > /tmp/action-body.json

curl -sk -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d @/tmp/action-body.json \
  "${VCO_API_BASE}/actions" \
  -w "\nHTTP_STATUS=%{http_code}\n"

## vRO Action Update (기존 — ID 조회 후 PUT)
ACTION_ID=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${VCO_API_BASE}/actions/com.vmk.dk/getOS/" | jq -r '.id')

curl -sk -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d @/tmp/action-body.json \
  "${VCO_API_BASE}/actions/${ACTION_ID}" \
  -w "\nHTTP_STATUS=%{http_code}\n"

## 입력 파라미터가 있는 액션의 JSON body 예 (getAdminUserByImage.js)
# 참고: getVMImage 는 입력 없음으로 변경됨(CCI clustervirtualmachineimages). 아래는 입력 있는 액션 예시.
jq -n \
  --rawfile script actions/com.vmk.dk/getAdminUserByImage.js \
  '{name:"getAdminUserByImage", module:"com.vmk.dk", version:"1.0.0",
    "output-type":"string",
    "input-parameters":[{"name":"imageName","type":"string","description":""}],
    script:$script}' \
  > /tmp/action-body.json

## CCI (Kubernetes-style) API — UI 의 Namespaces 페이지가 사용하는 경로
# 출처: HAR 캡처 (vcfa.dtvcf.lab.har, 2026-05-24).
# cloudapi (/cloudapi/v1/namespaces/{id}) 와 다른 representation.
# UI 가 표시하는 limit 분모 / "Edit limits" write 모두 이 경로.
#
# ⚠️ 자동화 미지원 (2026-05-24 검증):
#   브라우저 OIDC 세션 cookie 만 인증됨. cloudapi Bearer 토큰 / OIDC jwt-bearer 로
#   재발급한 UI client_id audience 토큰 / 모든 cookie 조합 시도 결과 401 (Unauthorized).
#   kube-apiserver 가 cloudapi REST 자격증명을 거부함. 본 섹션은 문서/참고용 (브라우저
#   DevTools 로 직접 호출 시 가능). 자동화는 cloudapi (위 섹션) 사용.

## CCI 베이스 URL
export CCI_BASE="https://${VCFA_FQDN}/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3"

## SupervisorNamespace LIST (전체 — UI 가 사용)
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${CCI_BASE}/supervisornamespaces?limit=500" | jq .
# 응답: .items[].metadata.{namespace=PROJECT, name=NS_NAME},
#       .items[].metadata.annotations["infrastructure.cci.vmware.com/id"]=cloudapi URN,
#       .items[].spec.classConfigOverrides.zones[]={name, cpuLimit, cpuReservation, memoryLimit, memoryReservation},
#       .items[].status.storageClasses[]={name, limit},
#       .items[].status.zones[]={name, cpuLimit, memoryLimit, markedForRemoval}     ← realized.

## SupervisorNamespace 단일 GET (top-level path)
# 단위: cpuLimit="<n>M" (=MHz), memoryLimit="<n>Mi" (=MiB), storage limit="<n>Mi"
curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
  "${CCI_BASE}/namespaces/${PROJECT}/supervisornamespaces/${NS_NAME}" | jq .

## SupervisorNamespace PATCH — CPU/Memory limit 변경 (UI 와 동일)
# ※ Content-Type 가 application/merge-patch+json 이어야 함. application/json 으로 보내면 jq deep-merge 안됨.
# ※ body 는 spec.classConfigOverrides.zones[] 만 포함하면 됨 (merge-patch 라 다른 필드는 보존).
# ※ 모든 zone 의 entry 를 명시. 단일 zone (domain-c9) 환경에서 검증됨.
curl -sk -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/merge-patch+json" \
  -H "Accept: application/json" \
  -d '{"spec":{"classConfigOverrides":{"zones":[{"name":"domain-c9","cpuLimit":"100000M","cpuReservation":"0M","memoryLimit":"102400Mi","memoryReservation":"0Mi"}]}}}' \
  "${CCI_BASE}/namespaces/${PROJECT}/supervisornamespaces/${NS_NAME}" \
  -w "\nHTTP_STATUS=%{http_code}\n"
# 응답: 200, .metadata.annotations["infrastructure.cci.vmware.com/update-task-id"] 로 비동기 task id 제공.
# .status.conditions[].type=="Realized" 가 다시 True 가 되면 반영 완료.

## SupervisorNamespace PATCH — Storage limit 변경 (UI 와 동일)
# 같은 endpoint. body 만 다름.
# spec.classConfigOverrides.storageClasses[].limit (단위 "<N>Mi"). 모든 storage class entry 명시.
curl -sk -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/merge-patch+json" \
  -H "Accept: application/json" \
  -d '{"spec":{"classConfigOverrides":{"storageClasses":[{"name":"obcluster-vsan-storage-policy","limit":"3072000Mi"}]}}}' \
  "${CCI_BASE}/namespaces/${PROJECT}/supervisornamespaces/${NS_NAME}" \
  -w "\nHTTP_STATUS=%{http_code}\n"
# 응답: 200. status.storageClasses[].limit 은 realize 후 갱신.
# (merge-patch 라 zones[] 같은 다른 spec.classConfigOverrides 항목은 보존됨)

## SupervisorNamespaceRegionalOptionsRequest — 클래스/존 한도 조회 (UI 의 Edit 폼이 사용)
# default* / max* 한도값 (예: maxCpuLimit, maxMemoryLimit, storageClasses[].{defaultLimit, maxLimit})
curl -sk -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"apiVersion":"infrastructure.cci.vmware.com/v1alpha1","kind":"SupervisorNamespaceRegionalOptionsRequest","spec":{"regionName":"'"${REGION}"'","className":"'"${CLASS}"'","includeOptions":["zones","vmClasses","storageClasses","contentSources","infraPolicies"]}}' \
  "https://${VCFA_FQDN}/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha1/namespaces/${PROJECT}/supervisornamespaceregionaloptionsrequests" \
  | jq .

## SupervisorNamespace 사용량 (used) 조회
curl -sk -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"apiVersion":"infrastructure.cci.vmware.com/v1alpha1","kind":"supervisornamespacemetricsrequests","spec":{"supervisorNamespaceRefs":[{"name":"'"${NS_NAME}"'","namespace":"'"${PROJECT}"'"}]}}' \
  "https://${VCFA_FQDN}/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha1/supervisornamespacemetricsrequests" \
  | jq '.status.items[]'
# 응답: zones[].{cpuUsed, memoryUsed}, storageClasses[].storageUsed (예: "921M", "400Mi", "41229Mi")

## cloudapi vs CCI 차이 요약
# cloudapi (PUT /cloudapi/v1/namespaces/{urn}) → cloudapi 의 resourceAllocation 만 갱신, UI 에는 미반영.
# CCI     (PATCH supervisornamespaces/{name}) → UI 와 동일 경로. UI 표시 = .spec.classConfigOverrides.zones[].
# Storage limit:
#   - cloudapi: storageClasses[].storageLimitMiB (PUT 으로 변경 가능, UI 미반영)
#   - CCI:      spec.classConfigOverrides.storageClasses[].limit (PATCH merge-patch+json, UI 일치)