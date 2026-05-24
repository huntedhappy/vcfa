#!/usr/bin/env bash

# ============================================================
# VCFA CloudAPI Helper Library
# - login_vcfa
# - vcfa_api_get
# - vcfa_api_post
# - vcfa_api_put
# - vcfa_api_delete
# ============================================================

set -o pipefail

: "${VCFA_API_VERSION:=9.1.0}"

# 이 lib 파일의 위치 (bash·zsh 양쪽 지원). 함수 안에서는 $0/BASH_SOURCE 가 다르게 동작하므로
# source 시점에 한 번 잡아둔다.
_VCFA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    return 1
  fi
}

vcfa_check_env() {
  require_cmd curl || return 1
  require_cmd jq || return 1

  if [[ -z "${VCFA_FQDN:-}" ]]; then
    echo "ERROR: VCFA_FQDN is not set." >&2
    return 1
  fi

  if [[ -z "${VCFA_USER:-}" ]]; then
    echo "ERROR: VCFA_USER is not set." >&2
    return 1
  fi

  if [[ -z "${VCFA_PASS:-}" ]]; then
    echo "ERROR: VCFA_PASS is not set." >&2
    return 1
  fi
}

# 내부: VCFA login 공통 구현. login_vcfa / login_vcfa_tenant 가 호출.
# Usage: _vcfa_login_basic <url> <basic-user>
#   <url>        — 전체 login URL (e.g. https://.../sessions 또는 .../sessions/provider)
#   <basic-user> — Basic Auth username (provider: "admin", tenant: "user@OrgName")
_vcfa_login_basic() {
  local url="${1:?_vcfa_login_basic: url required}"
  local basic_user="${2:?_vcfa_login_basic: basic_user required}"
  vcfa_check_env || return 1

  local response_file header_file http_code basic_auth
  response_file="$(mktemp /tmp/vcfa-login-response.XXXXXX)"
  header_file="$(mktemp /tmp/vcfa-login-header.XXXXXX)"
  basic_auth="$(printf '%s:%s' "${basic_user}" "${VCFA_PASS}" | base64 -w0 2>/dev/null \
    || printf '%s:%s' "${basic_user}" "${VCFA_PASS}" | base64)"

  http_code=$(
    curl -sk -X POST "${url}" \
      -H "Accept: application/json;version=${VCFA_API_VERSION}" \
      -H "Content-Type: application/json;version=${VCFA_API_VERSION}" \
      -H "Authorization: Basic ${basic_auth}" \
      -H "X-VMWARE-VCLOUD-ISSUE-REFRESH-TOKEN: true" \
      -D "${header_file}" \
      -o "${response_file}" \
      -w "%{http_code}"
  )

  if [[ "${http_code}" != "200" ]]; then
    echo "ERROR: VCFA login failed. HTTP=${http_code} (user=${basic_user}, url=${url})" >&2
    echo "===== response =====" >&2
    cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}" >&2
    rm -f "${response_file}" "${header_file}"
    return 1
  fi

  TOKEN=$(awk -F': ' 'tolower($1)=="x-vmware-vcloud-access-token" {print $2}' "${header_file}" | tr -d '\r')

  rm -f "${response_file}" "${header_file}"

  if [[ -z "${TOKEN}" ]]; then
    echo "ERROR: TOKEN not found in response header." >&2
    return 1
  fi

  export TOKEN
}

login_vcfa_provider() {
  _vcfa_login_basic "https://${VCFA_FQDN}/cloudapi/1.0.0/sessions/provider" "${VCFA_USER}"
}

login_vcfa_tenant() {
  : "${VCFA_TENANT_ORG:?ERROR: VCFA_TENANT_ORG 가 .env 에 설정되어야 함 (예: VCFA_TENANT_ORG=ProviderConsumptionOrg)}"
  _vcfa_login_basic "https://${VCFA_FQDN}/cloudapi/1.0.0/sessions" "${VCFA_USER}@${VCFA_TENANT_ORG}"
}

# Dispatcher: VCFA_TENANT_ORG 가 있으면 tenant, 없으면 provider.
login_vcfa() {
  if [[ -n "${VCFA_TENANT_ORG:-}" ]]; then
    login_vcfa_tenant
  else
    login_vcfa_provider
  fi
}

vcfa_api_request() {
  local method="$1"
  local url="$2"
  local body_file="${3:-}"

  if [[ -z "${TOKEN:-}" ]]; then
    login_vcfa || return 1
  fi

  local response_file
  local http_code

  response_file="$(mktemp /tmp/vcfa-api-response.XXXXXX)"

  if [[ -n "${body_file}" ]]; then
    http_code=$(
      curl -sk -X "${method}" \
        -H "Accept: application/json;version=${VCFA_API_VERSION}" \
        -H "Content-Type: application/json;version=${VCFA_API_VERSION}" \
        -H "Authorization: Bearer ${TOKEN}" \
        --data @"${body_file}" \
        -o "${response_file}" \
        -w "%{http_code}" \
        "${url}"
    )
  else
    http_code=$(
      curl -sk -X "${method}" \
        -H "Accept: application/json;version=${VCFA_API_VERSION}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -o "${response_file}" \
        -w "%{http_code}" \
        "${url}"
    )
  fi

  if [[ "${http_code}" == "401" ]]; then
    echo "TOKEN expired or invalid. Re-login..." >&2
    login_vcfa || {
      rm -f "${response_file}"
      return 1
    }

    if [[ -n "${body_file}" ]]; then
      http_code=$(
        curl -sk -X "${method}" \
          -H "Accept: application/json;version=${VCFA_API_VERSION}" \
          -H "Content-Type: application/json;version=${VCFA_API_VERSION}" \
          -H "Authorization: Bearer ${TOKEN}" \
          --data @"${body_file}" \
          -o "${response_file}" \
          -w "%{http_code}" \
          "${url}"
      )
    else
      http_code=$(
        curl -sk -X "${method}" \
          -H "Accept: application/json;version=${VCFA_API_VERSION}" \
          -H "Authorization: Bearer ${TOKEN}" \
          -o "${response_file}" \
          -w "%{http_code}" \
          "${url}"
      )
    fi
  fi

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo "ERROR: API failed. METHOD=${method} HTTP=${http_code}" >&2
    echo "URL=${url}" >&2
    echo "===== response =====" >&2
    cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}" >&2
    rm -f "${response_file}"
    return 1
  fi

  cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}"
  rm -f "${response_file}"
}

vcfa_api_get() {
  vcfa_api_request "GET" "$1"
}

vcfa_api_post() {
  vcfa_api_request "POST" "$1" "$2"
}

vcfa_api_put() {
  vcfa_api_request "PUT" "$1" "$2"
}

vcfa_api_delete() {
  vcfa_api_request "DELETE" "$1"
}

# ============================================================
# ORG helpers
# - vcfa_select_org : 대화식 ORG 선택 → .env 갱신 + 현재 셸 export
# ============================================================

# 내부: .env 의 key 를 멱등 갱신(있으면 교체, 없으면 추가)
_env_set() {
  local key="$1" val="$2"
  local f="${VCFA_ENV_FILE:-${_VCFA_LIB_DIR}/../.env}"
  [[ -f "$f" ]] || : > "$f"
  if grep -qE "^export ${key}=" "$f"; then
    sed -i "s|^export ${key}=.*|export ${key}=\"${val}\"|" "$f"
  else
    printf 'export %s="%s"\n' "$key" "$val" >> "$f"
  fi
}

# 내부: VCFA_ORG_NAME 또는 VCFA_ORG_ID 중 있는 것으로 ORG 식별 보장.
# - NAME 만 있으면 /orgs 에서 ID 찾아 VCFA_ORG_ID 세팅 (한 번 resolve 후 _VCFA_ORG_CACHED_NAME 캐시)
# - ID 만 있으면 그대로
# - 둘 다 없으면 에러
_vcfa_ensure_org_id() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  if [[ -n "${VCFA_ORG_NAME:-}" ]]; then
    if [[ "${_VCFA_ORG_CACHED_NAME:-}" == "${VCFA_ORG_NAME}" ]] && [[ -n "${VCFA_ORG_ID:-}" ]]; then
      return 0   # 캐시 hit — 같은 NAME 으로 이미 resolve 됨
    fi
    require_cmd jq || return 1
    local id
    id=$(vcfa_api_get "https://${VCFA_FQDN}/cloudapi/1.0.0/orgs?page=1&pageSize=128" \
         | jq -r --arg n "${VCFA_ORG_NAME}" '.values[]? | select(.name==$n) | .id' | head -1)
    if [[ -z "$id" ]]; then
      echo "ERROR: ORG name '${VCFA_ORG_NAME}' 을(를) 찾을 수 없습니다." >&2
      echo "       사용 가능한 ORG: vcfa_list_orgs" >&2
      return 1
    fi
    VCFA_ORG_ID="$id"
    _VCFA_ORG_CACHED_NAME="${VCFA_ORG_NAME}"
    return 0
  fi
  if [[ -z "${VCFA_ORG_ID:-}" ]]; then
    echo "ERROR: VCFA_ORG_NAME 또는 VCFA_ORG_ID 가 필요합니다." >&2
    echo "       권장: vcfa_select_org   또는   VCFA_ORG_NAME=Org1 <명령>" >&2
    return 1
  fi
}

# 내부: 현재 ORG 의 모든 VDC × 그 안의 namespace 를 하나의 JSON 배열로 반환.
# 각 element 에 _vdcId / _vdcName 메타 추가.
# ★ 사전조건: VCFA_ORG_ID 가 이미 세팅되어 있어야 함 (caller 가 _vcfa_ensure_org_id 먼저 호출).
#   이 함수가 $(...) 안에서 호출되면 ensure 가 세팅한 ID 가 subshell 에 갇혀 caller 에 안 보이기 때문.
# 내부: tenant 모드용 namespace 목록 (CCI Kubernetes API 사용).
# /cloudapi/v1/virtualDatacenters 가 tenant 토큰엔 403 이라 우회.
# 출력 JSON 은 cloudapi 버전과 비슷한 shape: [{id, name, status, _vdcName, _projectName, ...}]
_vcfa_list_namespaces_cci_json() {
  require_cmd jq || return 1
  local resp; resp=$(mktemp /tmp/vcfa-cci-ns.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=500" > "${resp}" \
    || { rm -f "${resp}"; return 1; }

  # CCI 응답 → cloudapi 와 비슷한 형태로 정규화. _vdcName 은 region 으로 대체.
  jq '[.items[]? | {
    id: .metadata.annotations["infrastructure.cci.vmware.com/id"],
    name: .metadata.name,
    status: (.status.phase // "?"),
    _projectName: .metadata.namespace,
    _vdcName: .spec.regionName,
    _zones: [.spec.classConfigOverrides.zones[]? | {name, cpuLimit, memoryLimit}],
    _storage: [.status.storageClasses[]? | {name, limit}]
  }]' "${resp}"
  rm -f "${resp}"
}

# 내부: provider 모드용 namespace 목록 (cloudapi VDC enumeration).
_vcfa_list_namespaces_cloudapi_json() {
  : "${VCFA_ORG_ID:?_vcfa_list_namespaces_cloudapi_json: VCFA_ORG_ID required}"
  require_cmd jq || return 1

  local vdcs_file; vdcs_file=$(mktemp /tmp/vcfa-vdcs.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters?page=1&pageSize=128" > "${vdcs_file}" \
    || { rm -f "${vdcs_file}"; return 1; }

  local pairs; pairs=$(jq -r --arg id "${VCFA_ORG_ID}" '.values[] | select(.org.id == $id) | "\(.id)\t\(.name)"' "${vdcs_file}")
  rm -f "${vdcs_file}"

  local combined; combined=$(mktemp /tmp/vcfa-ns-all.XXXXXX)
  echo "[]" > "${combined}"

  if [[ -n "$pairs" ]]; then
    while IFS=$'\t' read -r vdc_id vdc_name; do
      [[ -z "$vdc_id" ]] && continue
      local one; one=$(mktemp /tmp/vcfa-ns-one.XXXXXX)
      vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters/${vdc_id}/namespaces?page=1&pageSize=128" \
        > "${one}" 2>/dev/null || { rm -f "${one}"; continue; }
      jq -s --arg vid "$vdc_id" --arg vname "$vdc_name" '
        .[0] + ((.[1].values // []) | map(. + {_vdcId: $vid, _vdcName: $vname}))
      ' "${combined}" "${one}" > "${combined}.new"
      mv "${combined}.new" "${combined}"
      rm -f "${one}"
    done <<< "$pairs"
  fi

  cat "${combined}"
  rm -f "${combined}"
}

# Dispatcher: tenant 모드면 CCI, 아니면 cloudapi.
_vcfa_list_namespaces_json() {
  if [[ -n "${VCFA_TENANT_ORG:-}" ]]; then
    _vcfa_list_namespaces_cci_json
  else
    _vcfa_list_namespaces_cloudapi_json
  fi
}

vcfa_list_namespaces() {
  # tenant 모드면 _vcfa_ensure_org_id 생략 가능 (CCI 가 user scope 로 자동 필터). provider 면 필수.
  if [[ -z "${VCFA_TENANT_ORG:-}" ]]; then
    _vcfa_ensure_org_id || return 1
  fi
  local json; json=$(_vcfa_list_namespaces_json) || return 1
  echo "ORG: ${VCFA_ORG_NAME:-${VCFA_TENANT_ORG:-?}} (${VCFA_ORG_ID:-tenant})"
  local n; n=$(echo "$json" | jq 'length')
  if [[ "$n" -eq 0 ]]; then
    echo "(namespace 없음)"
    return 0
  fi
  echo ""
  # tenant (CCI) 와 provider (cloudapi) 의 응답 shape 가 달라 컬럼 분기.
  if [[ -n "${VCFA_TENANT_ORG:-}" ]]; then
    echo "$json" | jq -r '
      ["NAME", "PROJECT", "REGION", "STATUS", "ID"],
      (.[]
        | [.name, ._projectName, ._vdcName, .status, .id])
      | @tsv' \
      | column -t -s $'\t'
  else
    echo "$json" | jq -r '
      ["NAME", "VDC", "STATUS", "CPU_USED/LIMIT(MHz)", "MEM_USED/LIMIT(MiB)", "ID"],
      (.[]
        | . as $ns
        | (.zonalResourceAllocation[0].resourceAllocation // {}) as $r
        | [$ns.name,
           $ns._vdcName,
           $ns.status,
           "\($r.cpuUsedMHz // 0)/\($r.cpuLimitMHz // 0)",
           "\($r.memoryUsedMiB // 0)/\($r.memoryLimitMiB // 0)",
           $ns.id])
      | @tsv' \
      | column -t -s $'\t'
  fi
}

vcfa_select_namespace() {
  # 인터랙티브 선택 → 상세 출력 + VCFA_NS_ID / VCFA_NS_NAME 셸에 export
  if [[ -z "${VCFA_TENANT_ORG:-}" ]]; then
    _vcfa_ensure_org_id || return 1
  fi
  local json; json=$(_vcfa_list_namespaces_json) || return 1
  local n; n=$(echo "$json" | jq 'length')
  if [[ "$n" -eq 0 ]]; then
    echo "(namespace 없음)" >&2
    return 1
  fi

  echo "선택 가능한 Namespace (ORG: ${VCFA_ORG_NAME:-${VCFA_TENANT_ORG:-?}}):"
  if [[ -n "${VCFA_TENANT_ORG:-}" ]]; then
    echo "$json" | jq -r '
      to_entries[]
      | "  \(.key+1 | tostring | (" "*(2-length) + .))) \(.value.name)  [\(.value.status)]  project=\(.value._projectName)  region=\(.value._vdcName)"'
  else
    echo "$json" | jq -r '
      to_entries[]
      | "  \(.key+1 | tostring | (" "*(2-length) + .))) \(.value.name)  [\(.value.status)]  vdc=\(.value._vdcName)"'
  fi

  printf "번호 [1-%s]: " "$n"
  local choice; read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > n )); then
    echo "ERROR: invalid choice." >&2
    return 1
  fi

  local idx=$((choice-1))
  echo ""
  echo "=== 상세 ==="
  echo "$json" | jq ".[$idx]"

  export VCFA_NS_ID=$(echo "$json" | jq -r ".[$idx].id")
  export VCFA_NS_NAME=$(echo "$json" | jq -r ".[$idx].name")
  echo ""
  echo "(셸에 export: VCFA_NS_NAME=${VCFA_NS_NAME}, VCFA_NS_ID=${VCFA_NS_ID})"
}

# 내부: 202 응답 Location 헤더의 task URL 로 폴링 → success/error/timeout 반환
# Usage: _vcfa_wait_task <task-url> [timeout_sec=120]
_vcfa_wait_task() {
  local url="${1:?task url required}"
  local timeout="${2:-120}"
  require_cmd jq || return 1
  # zsh 에서 'status' 는 readonly 예약어 → task_st 사용
  local start=$SECONDS body task_st err elapsed
  while true; do
    body=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/*+json;version=${VCFA_API_VERSION:-9.1.0}" "${url}")
    task_st=$(echo "$body" | jq -r '.status // ""')
    case "$task_st" in
      success)
        elapsed=$((SECONDS - start))
        echo "  task: success (${elapsed}s)"
        return 0 ;;
      error|aborted)
        err=$(echo "$body" | jq -r '.error.message // .details // "no detail"')
        echo "  task: ${task_st} — ${err}" >&2
        return 1 ;;
    esac
    (( SECONDS - start > timeout )) && { echo "  task: timeout (${timeout}s, last status=${task_st})" >&2; return 1; }
    sleep 2
  done
}

# 내부: namespace PUT 공통 — JSON body 받아 PUT → Location 헤더의 task 폴링
_vcfa_namespace_put_and_wait() {
  local ns_id="${1:?ns_id required}"
  local body_file="${2:?body_file required}"

  local hdr resp code
  hdr=$(mktemp /tmp/vcfa-put-hdr.XXXXXX)
  resp=$(mktemp /tmp/vcfa-put-resp.XXXXXX)
  code=$(curl -sk -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json;version=${VCFA_API_VERSION:-9.1.0}" \
    -H "Content-Type: application/json;version=${VCFA_API_VERSION:-9.1.0}" \
    -d @"${body_file}" \
    -D "${hdr}" \
    -o "${resp}" \
    -w "%{http_code}" \
    "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${ns_id}")

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "ERROR: PUT failed HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${hdr}" "${resp}"; return 1
  fi

  echo "  PUT accepted (HTTP=${code})"

  # 202 면 Location 헤더에 task URL 있음 → 폴링
  if [[ "$code" == "202" ]]; then
    local task_url
    task_url=$(awk -F': ' 'tolower($1)=="location" {print $2}' "${hdr}" | tr -d '\r')
    if [[ -n "$task_url" ]]; then
      _vcfa_wait_task "${task_url}" || { rm -f "${hdr}" "${resp}"; return 1; }
    fi
  fi

  rm -f "${hdr}" "${resp}"
  return 0
}

vcfa_namespace_show_limit() {
  # 현재 선택된 namespace (VCFA_NS_ID) 의 zone별 limit/예약/사용량 (친근 단위 + raw).
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  local ns_id="${1:-${VCFA_NS_ID}}"
  if [[ -z "$ns_id" ]]; then
    echo "ERROR: namespace ID 가 필요합니다 (vcfa_select_namespace 먼저 또는 인자로 전달)" >&2
    return 1
  fi
  # 응답을 tmp 파일로 받아 두 번 read (headers / tables 분리)
  local nsj; nsj=$(mktemp /tmp/vcfa-ns.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${ns_id}" > "${nsj}" \
    || { rm -f "${nsj}"; return 1; }

  # 1) 헤더 (자유 텍스트)
  jq -r '
    "ORG:     \(.organization.name)   (\(.organization.id))",
    "PROJECT: \(.projectAssignment.name)",
    "REGION:  \(.region.name)   VPC: \(.virtualPrivateCloudName // "-")",
    "NS:      \(.name)   STATUS: \(.status)"
  ' "${nsj}"

  # 2) Compute 표
  echo ""
  echo "[Compute — zonalResourceAllocation]"
  jq -r '
    def cpu_fmt:
      if . >= 1000000 then "\( ((. / 1000000) * 10 | round) / 10 ) THz"
      elif . >= 1000  then "\( ((. / 1000)    * 10 | round) / 10 ) GHz"
      else "\(.) MHz" end;
    def mem_fmt:
      if . >= 1048576 then "\( ((. / 1048576) * 10 | round) / 10 ) TiB"
      elif . >= 1024  then "\( ((. / 1024)    * 10 | round) / 10 ) GiB"
      else "\(.) MiB" end;
    (["ZONE","CPU_LIMIT","CPU_RSV","MEM_LIMIT","MEM_RSV","CPU_USED","MEM_USED"] | @tsv),
    (.zonalResourceAllocation[]
      | .resourceAllocation as $r
      | [.zone.name,
         ($r.cpuLimitMHz | cpu_fmt),
         ($r.cpuReservationMHz | cpu_fmt),
         ($r.memoryLimitMiB | mem_fmt),
         ($r.memoryReservationMiB | mem_fmt),
         (($r.cpuUsedMHz // 0) | cpu_fmt),
         (($r.memoryUsedMiB // 0) | mem_fmt)]
      | @tsv)
  ' "${nsj}" | column -t -s $'\t'

  # 3) Storage 표
  echo ""
  echo "[Storage — storageClasses]"
  jq -r '
    def mem_fmt:
      if . >= 1048576 then "\( ((. / 1048576) * 10 | round) / 10 ) TiB"
      elif . >= 1024  then "\( ((. / 1024)    * 10 | round) / 10 ) GiB"
      else "\(.) MiB" end;
    (["STORAGE_CLASS","LIMIT","REALIZED"] | @tsv),
    ((.storageClasses // [])[]?
      | [.storageClass.name,
         (.storageLimitMiB | mem_fmt),
         (.realizedStorageLimitMiB | mem_fmt)]
      | @tsv)
  ' "${nsj}" | column -t -s $'\t'

  rm -f "${nsj}"
}

vcfa_namespace_set_limit() {
  # Usage: vcfa_namespace_set_limit KEY=VALUE [KEY=VALUE ...]
  # 사전조건: VCFA_NS_ID 가 export 되어 있을 것 (vcfa_select_namespace 로 잡힘)
  #
  # 사용 가능한 KEY (정수, 모든 zone 에 동일 적용):
  #   cpu_limit_mhz   → cpuLimitMHz
  #   cpu_rsv_mhz     → cpuReservationMHz
  #   mem_limit_mib   → memoryLimitMiB
  #   mem_rsv_mib     → memoryReservationMiB
  #
  # 예: vcfa_namespace_set_limit cpu_limit_mhz=80000 mem_limit_mib=80000
  #
  # 동작: GET 현재 → resourceAllocation 수정 → PUT 으로 통째 replace
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1
  local ns_id="${VCFA_NS_ID:?ERROR: VCFA_NS_ID 없음 — vcfa_select_namespace 먼저 실행}"

  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage: vcfa_namespace_set_limit KEY=VALUE [KEY=VALUE ...]

CPU  KEY: cpu_limit_{mhz,ghz,thz}, cpu_rsv_{mhz,ghz,thz}
MEM  KEY: mem_limit_{mib,gib,tib}, mem_rsv_{mib,gib,tib}

값은 정수. 단위는 자동 환산되어 API 기본단위(MHz / MiB) 로 PUT.
  cpu_*_ghz=N  → N * 1000     MHz
  cpu_*_thz=N  → N * 1000000  MHz
  mem_*_gib=N  → N * 1024     MiB
  mem_*_tib=N  → N * 1048576  MiB  (1024 * 1024)

예:
  vcfa_namespace_set_limit cpu_limit_ghz=80 mem_limit_gib=80
  vcfa_namespace_set_limit cpu_limit_mhz=80000 mem_limit_mib=81920   # 동일
  vcfa_namespace_set_limit cpu_rsv_ghz=10 mem_rsv_gib=8
EOF
    return 1
  fi

  # 인자 파싱 → 단위 환산 → jq 필터 + --argjson 인자
  local jq_args=() jq_filter=".zonalResourceAllocation |= map("
  local first=1 k v api_k mult final_v
  for arg in "$@"; do
    k="${arg%%=*}"; v="${arg#*=}"
    mult=1
    case "$k" in
      cpu_limit_mhz) api_k="cpuLimitMHz"       ; mult=1       ;;
      cpu_limit_ghz) api_k="cpuLimitMHz"       ; mult=1000    ;;
      cpu_limit_thz) api_k="cpuLimitMHz"       ; mult=1000000 ;;
      cpu_rsv_mhz)   api_k="cpuReservationMHz" ; mult=1       ;;
      cpu_rsv_ghz)   api_k="cpuReservationMHz" ; mult=1000    ;;
      cpu_rsv_thz)   api_k="cpuReservationMHz" ; mult=1000000 ;;
      mem_limit_mib) api_k="memoryLimitMiB"        ; mult=1       ;;
      mem_limit_gib) api_k="memoryLimitMiB"        ; mult=1024    ;;
      mem_limit_tib) api_k="memoryLimitMiB"        ; mult=1048576 ;;
      mem_rsv_mib)   api_k="memoryReservationMiB"  ; mult=1       ;;
      mem_rsv_gib)   api_k="memoryReservationMiB"  ; mult=1024    ;;
      mem_rsv_tib)   api_k="memoryReservationMiB"  ; mult=1048576 ;;
      cpu_*)
        echo "ERROR: 잘못된 key '${k}'. CPU 단위는 mhz/ghz/thz 만 가능합니다." >&2
        echo "       (memory 단위 mib/gib/tib 를 cpu_* 에 쓰지 마세요)" >&2
        echo "       예: cpu_limit_ghz, cpu_rsv_mhz" >&2
        return 1 ;;
      mem_*)
        echo "ERROR: 잘못된 key '${k}'. Memory 단위는 mib/gib/tib 만 가능합니다." >&2
        echo "       (cpu 단위 mhz/ghz/thz 를 mem_* 에 쓰지 마세요)" >&2
        echo "       예: mem_limit_gib, mem_rsv_mib" >&2
        return 1 ;;
      *)
        echo "ERROR: unknown key '${k}'" >&2
        echo "       사용 가능: cpu_{limit,rsv}_{mhz,ghz,thz}, mem_{limit,rsv}_{mib,gib,tib}" >&2
        return 1 ;;
    esac

    if ! [[ "$v" =~ ^[0-9]+$ ]]; then
      echo "ERROR: '${k}' 의 값은 정수여야 함, 받은 값='${v}'" >&2
      return 1
    fi

    final_v=$((v * mult))
    [[ $first -eq 1 ]] || jq_filter+=" | "
    jq_filter+=".resourceAllocation.${api_k} = \$${api_k}"
    jq_args+=(--argjson "${api_k}" "${final_v}")
    first=0
  done
  jq_filter+=")"

  # 1) 현재 namespace GET
  local cur; cur=$(mktemp /tmp/vcfa-ns-cur.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${ns_id}" > "${cur}" \
    || { rm -f "${cur}"; return 1; }

  # 2) 변경본 만들기
  local patched; patched=$(mktemp /tmp/vcfa-ns-new.XXXXXX)
  jq "${jq_args[@]}" "${jq_filter}" "${cur}" > "${patched}" \
    || { rm -f "${cur}" "${patched}"; return 1; }

  echo "변경 미리보기 (zonalResourceAllocation[].resourceAllocation):"
  echo "  === BEFORE ===";  jq -c '.zonalResourceAllocation[] | {zone: .zone.name, ra: .resourceAllocation | {cpuLimitMHz, cpuReservationMHz, memoryLimitMiB, memoryReservationMiB}}' "${cur}"
  echo "  === AFTER  ===";  jq -c '.zonalResourceAllocation[] | {zone: .zone.name, ra: .resourceAllocation | {cpuLimitMHz, cpuReservationMHz, memoryLimitMiB, memoryReservationMiB}}' "${patched}"

  # 3) PUT + task wait
  _vcfa_namespace_put_and_wait "${ns_id}" "${patched}"
  local rc=$?
  rm -f "${cur}" "${patched}"
  return $rc
}

vcfa_namespace_set_storage_limit() {
  # Usage: vcfa_namespace_set_storage_limit KEY=VALUE [KEY=VALUE ...]
  # 사전조건: VCFA_NS_ID export (vcfa_select_namespace)
  #
  # KEY (정수, 모든 storage class 에 동일 적용):
  #   storage_limit_mib  → storageLimitMiB
  #   storage_limit_gib  → storageLimitMiB × 1024
  #   storage_limit_tib  → storageLimitMiB × 1048576
  #
  # 예: vcfa_namespace_set_storage_limit storage_limit_tib=2
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1
  local ns_id="${VCFA_NS_ID:?ERROR: VCFA_NS_ID 없음 — vcfa_select_namespace 먼저}"

  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage: vcfa_namespace_set_storage_limit KEY=VALUE [KEY=VALUE ...]
  storage_limit_mib=N  / storage_limit_gib=N  / storage_limit_tib=N
  (모든 storage class 에 동일 적용)

예:
  vcfa_namespace_set_storage_limit storage_limit_tib=2
  vcfa_namespace_set_storage_limit storage_limit_gib=2000
  vcfa_namespace_set_storage_limit storage_limit_mib=2048000
EOF
    return 1
  fi

  # 하나 이상 값 들어와도 마지막 것만 적용 (단일 필드만 있음). 우선 단순화: 첫 인자만 처리.
  local arg="$1"; local k="${arg%%=*}" v="${arg#*=}" mult=1 final_v
  case "$k" in
    storage_limit_mib) mult=1       ;;
    storage_limit_gib) mult=1024    ;;
    storage_limit_tib) mult=1048576 ;;
    *) echo "ERROR: unknown key '${k}' (storage_limit_mib/gib/tib 만 가능)" >&2; return 1 ;;
  esac
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "ERROR: '${k}' 의 값은 정수여야 함, 받은 값='${v}'" >&2; return 1
  fi
  final_v=$((v * mult))

  # 1) 현재 GET
  local cur patched
  cur=$(mktemp /tmp/vcfa-ns-cur.XXXXXX)
  patched=$(mktemp /tmp/vcfa-ns-new.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/namespaces/${ns_id}" > "${cur}" \
    || { rm -f "${cur}" "${patched}"; return 1; }

  # 2) storageClasses[].storageLimitMiB 전체 변경
  jq --argjson v "${final_v}" '
    .storageClasses |= map(.storageLimitMiB = $v)
  ' "${cur}" > "${patched}" || { rm -f "${cur}" "${patched}"; return 1; }

  echo "변경 미리보기 (storageClasses[].storageLimitMiB):"
  echo "  === BEFORE ===";  jq -c '.storageClasses[] | {class: .storageClass.name, limitMiB: .storageLimitMiB, realizedMiB: .realizedStorageLimitMiB}' "${cur}"
  echo "  === AFTER  ===";  jq -c '.storageClasses[] | {class: .storageClass.name, limitMiB: .storageLimitMiB}' "${patched}"

  # 3) PUT + task wait
  _vcfa_namespace_put_and_wait "${ns_id}" "${patched}"
  local rc=$?
  rm -f "${cur}" "${patched}"
  return $rc
}

# ============================================================
# CCI namespace 한도 수정 (tenant 모드 전용 — UI 와 동일 경로)
#
# 위 vcfa_namespace_set_limit / set_storage_limit 은 cloudapi (/cloudapi/v1/namespaces)
# PUT 로 백엔드는 갱신하지만 UI Namespaces 페이지 표시값과 동기화 안됨.
# 아래 *_cci 함수들은 UI 가 쓰는 /cci/kubernetes/apis/... 경로 (PATCH merge-patch+json)
# 를 사용해 UI 와 백엔드를 동시 갱신.
#
# 검증된 PATCH body (HAR 캡처 + tenant 토큰 200):
#   CPU/Memory: {"spec":{"classConfigOverrides":{"zones":[{"name":"<z>","cpuLimit":"<n>M","cpuReservation":"0M","memoryLimit":"<n>Mi","memoryReservation":"0Mi"}]}}}
#   Storage:    {"spec":{"classConfigOverrides":{"storageClasses":[{"name":"<sc>","limit":"<n>Mi"}]}}}
#
# 전제: source scripts/session.sh .env.tenant 후 사용.
# ============================================================

_cci_base() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  : "${TOKEN:?ERROR: TOKEN is not set}"
  echo "https://${VCFA_FQDN}/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3"
}

# 내부: name 또는 cloudapi URN 으로 SupervisorNamespace {project, name} 해석.
# stdout: "<project>\t<name>"
_cci_resolve_ns() {
  local key="${1:?_cci_resolve_ns: key required (name 또는 cloudapi URN)}"
  require_cmd jq || return 1
  local base; base=$(_cci_base) || return 1
  local resp; resp=$(mktemp /tmp/cci-list.XXXXXX)
  local code
  code=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "${base}/supervisornamespaces?limit=500" -o "${resp}" -w "%{http_code}")
  if [[ "$code" != "200" ]]; then
    echo "ERROR: CCI list HTTP=${code} (tenant 모드 + project 멤버 user 인지 확인)" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  local match
  match=$(jq -r --arg k "$key" '
    .items[]
    | select(.metadata.name == $k
             or .metadata.annotations["infrastructure.cci.vmware.com/id"] == $k)
    | "\(.metadata.namespace)\t\(.metadata.name)"' "${resp}")
  rm -f "${resp}"

  if [[ -z "$match" ]]; then
    echo "ERROR: CCI SupervisorNamespace 를 찾을 수 없음 (key=${key})" >&2
    return 1
  fi
  echo "$match" | head -1
}

_cci_get_ns() {
  local project="${1:?project required}"
  local name="${2:?name required}"
  local base; base=$(_cci_base) || return 1
  local resp; resp=$(mktemp /tmp/cci-get.XXXXXX)
  local code
  code=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "${base}/namespaces/${project}/supervisornamespaces/${name}" -o "${resp}" -w "%{http_code}")
  if [[ "$code" != "200" ]]; then
    echo "ERROR: CCI GET HTTP=${code} (project=${project} name=${name})" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi
  cat "${resp}"
  rm -f "${resp}"
}

# CCI 기준 limit/realized — UI Namespaces 페이지가 표시하는 값과 동일 원천.
vcfa_namespace_show_limit_cci() {
  require_cmd jq || return 1
  local key="${1:-${VCFA_NS_NAME:-${VCFA_NS_ID:-}}}"
  if [[ -z "$key" ]]; then
    echo "ERROR: namespace 식별자 필요 — 인자 또는 vcfa_select_namespace 먼저" >&2
    return 1
  fi
  local pair; pair=$(_cci_resolve_ns "$key") || return 1
  local project="${pair%%$'\t'*}" name="${pair##*$'\t'}"

  local nsj; nsj=$(mktemp /tmp/cci-ns.XXXXXX)
  _cci_get_ns "$project" "$name" > "${nsj}" || { rm -f "${nsj}"; return 1; }

  jq -r '
    "PROJECT: \(.metadata.namespace)",
    "NS:      \(.metadata.name)   class=\(.spec.className)   region=\(.spec.regionName)",
    "PHASE:   \(.status.phase)   conditions: \([.status.conditions[]? | (.type + "=" + .status)] | join(", "))"
  ' "${nsj}"

  echo ""
  echo "[Compute — spec.classConfigOverrides.zones (= UI 표시 원천)]"
  jq -r '
    def m_to_friendly:
      (capture("^(?<n>[0-9]+)M$") | (.n | tonumber)) as $n
      | if   $n >= 1000000 then "\(((($n/1000000)*10)|round)/10) THz"
        elif $n >= 1000    then "\(((($n/1000)*10)|round)/10) GHz"
        else "\($n) MHz" end;
    def mi_to_friendly:
      (capture("^(?<n>[0-9]+)Mi$") | (.n | tonumber)) as $n
      | if   $n >= 1048576 then "\(((($n/1048576)*10)|round)/10) TiB"
        elif $n >= 1024    then "\(((($n/1024)*10)|round)/10) GiB"
        else "\($n) MiB" end;
    (["ZONE","CPU_LIMIT","CPU_RSV","MEM_LIMIT","MEM_RSV"] | @tsv),
    ((.spec.classConfigOverrides.zones // [])[]
      | [.name, (.cpuLimit|m_to_friendly), (.cpuReservation|m_to_friendly),
         (.memoryLimit|mi_to_friendly), (.memoryReservation|mi_to_friendly)]
      | @tsv)
  ' "${nsj}" | column -t -s $'\t'

  echo ""
  echo "[Storage — spec.classConfigOverrides.storageClasses (= UI 표시 원천)]"
  jq -r '
    def mi_to_friendly:
      (capture("^(?<n>[0-9]+)Mi$") | (.n | tonumber)) as $n
      | if   $n >= 1048576 then "\(((($n/1048576)*10)|round)/10) TiB"
        elif $n >= 1024    then "\(((($n/1024)*10)|round)/10) GiB"
        else "\($n) MiB" end;
    (["STORAGE_CLASS","LIMIT"] | @tsv),
    ((.spec.classConfigOverrides.storageClasses // [])[]
      | [.name, (.limit | mi_to_friendly)] | @tsv),
    (if ((.spec.classConfigOverrides.storageClasses // []) | length) == 0
     then ["(no override — class default 적용)","-"] | @tsv else empty end)
  ' "${nsj}" | column -t -s $'\t'

  echo ""
  echo "[Storage — status.storageClasses (realized)]"
  jq -r '
    def mi_to_friendly:
      (capture("^(?<n>[0-9]+)Mi$") | (.n | tonumber)) as $n
      | if   $n >= 1048576 then "\(((($n/1048576)*10)|round)/10) TiB"
        elif $n >= 1024    then "\(((($n/1024)*10)|round)/10) GiB"
        else "\($n) MiB" end;
    (["STORAGE_CLASS","LIMIT"] | @tsv),
    ((.status.storageClasses // [])[] | [.name, (.limit|mi_to_friendly)] | @tsv)
  ' "${nsj}" | column -t -s $'\t'

  rm -f "${nsj}"
}

# CCI PATCH 로 namespace 의 CPU/Memory limit 수정 (UI 와 동일 경로).
# Usage: vcfa_namespace_set_limit_cci KEY=VALUE [KEY=VALUE ...]
#   cpu_limit_{mhz,ghz,thz}, cpu_rsv_{mhz,ghz,thz}
#   mem_limit_{mib,gib,tib}, mem_rsv_{mib,gib,tib}
vcfa_namespace_set_limit_cci() {
  require_cmd jq || return 1

  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage: vcfa_namespace_set_limit_cci KEY=VALUE [KEY=VALUE ...]
  CPU: cpu_limit_{mhz,ghz,thz}, cpu_rsv_{mhz,ghz,thz}    → 단위 "<n>M"
  MEM: mem_limit_{mib,gib,tib}, mem_rsv_{mib,gib,tib}    → 단위 "<n>Mi"
전제: VCFA_NS_NAME export 됐을 것 (vcfa_select_namespace), tenant 모드.

예:
  vcfa_namespace_set_limit_cci cpu_limit_ghz=80 mem_limit_gib=80
  vcfa_namespace_set_limit_cci cpu_rsv_ghz=10
EOF
    return 1
  fi

  local key="${VCFA_NS_NAME:-${VCFA_NS_ID:-}}"
  if [[ -z "$key" ]]; then
    echo "ERROR: VCFA_NS_NAME 필요 — vcfa_select_namespace 먼저" >&2
    return 1
  fi
  local pair; pair=$(_cci_resolve_ns "$key") || return 1
  local project="${pair%%$'\t'*}" ns_name="${pair##*$'\t'}"

  # 인자 → 단위 환산 → 키별 변수
  local cpu_l="" cpu_r="" mem_l="" mem_r=""
  local k v mult vn
  for arg in "$@"; do
    k="${arg%%=*}"; v="${arg#*=}"
    [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: '${k}' 값은 정수, 받은='${v}'" >&2; return 1; }
    case "$k" in
      cpu_limit_mhz) mult=1;       vn=$((v*mult)); cpu_l="${vn}M" ;;
      cpu_limit_ghz) mult=1000;    vn=$((v*mult)); cpu_l="${vn}M" ;;
      cpu_limit_thz) mult=1000000; vn=$((v*mult)); cpu_l="${vn}M" ;;
      cpu_rsv_mhz)   mult=1;       vn=$((v*mult)); cpu_r="${vn}M" ;;
      cpu_rsv_ghz)   mult=1000;    vn=$((v*mult)); cpu_r="${vn}M" ;;
      cpu_rsv_thz)   mult=1000000; vn=$((v*mult)); cpu_r="${vn}M" ;;
      mem_limit_mib) mult=1;       vn=$((v*mult)); mem_l="${vn}Mi" ;;
      mem_limit_gib) mult=1024;    vn=$((v*mult)); mem_l="${vn}Mi" ;;
      mem_limit_tib) mult=1048576; vn=$((v*mult)); mem_l="${vn}Mi" ;;
      mem_rsv_mib)   mult=1;       vn=$((v*mult)); mem_r="${vn}Mi" ;;
      mem_rsv_gib)   mult=1024;    vn=$((v*mult)); mem_r="${vn}Mi" ;;
      mem_rsv_tib)   mult=1048576; vn=$((v*mult)); mem_r="${vn}Mi" ;;
      cpu_*) echo "ERROR: CPU 단위는 mhz/ghz/thz (받은 '${k}')" >&2; return 1 ;;
      mem_*) echo "ERROR: Memory 단위는 mib/gib/tib (받은 '${k}')" >&2; return 1 ;;
      *)     echo "ERROR: unknown key '${k}'" >&2; return 1 ;;
    esac
  done

  # 현재 상태 GET — zone 이름 + 미지정 키 보존
  local cur; cur=$(mktemp /tmp/cci-cur.XXXXXX)
  _cci_get_ns "$project" "$ns_name" > "${cur}" || { rm -f "${cur}"; return 1; }

  local body; body=$(mktemp /tmp/cci-patch.XXXXXX)
  jq --arg cL "$cpu_l" --arg cR "$cpu_r" --arg mL "$mem_l" --arg mR "$mem_r" '
    {spec:{classConfigOverrides:{zones:
      ((.spec.classConfigOverrides.zones // []) | map({
        name:.name,
        cpuLimit:          (if $cL != "" then $cL else .cpuLimit          end),
        cpuReservation:    (if $cR != "" then $cR else .cpuReservation    end),
        memoryLimit:       (if $mL != "" then $mL else .memoryLimit       end),
        memoryReservation: (if $mR != "" then $mR else .memoryReservation end)
      }))
    }}}' "${cur}" > "${body}" || { rm -f "${cur}" "${body}"; return 1; }

  echo "변경 미리보기 (spec.classConfigOverrides.zones):"
  echo "  BEFORE: $(jq -c '.spec.classConfigOverrides.zones // []' "${cur}")"
  echo "  PATCH:  $(jq -c '.spec.classConfigOverrides.zones'      "${body}")"

  local base; base=$(_cci_base) || { rm -f "${cur}" "${body}"; return 1; }
  local resp; resp=$(mktemp /tmp/cci-patch-resp.XXXXXX)
  local code
  code=$(curl -sk -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/merge-patch+json" \
    -H "Accept: application/json" \
    -d @"${body}" \
    -o "${resp}" -w "%{http_code}" \
    "${base}/namespaces/${project}/supervisornamespaces/${ns_name}")
  rm -f "${cur}" "${body}"

  if [[ "${code}" -lt 200 || "${code}" -ge 300 ]]; then
    echo "ERROR: CCI PATCH HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  echo "OK: PATCH accepted (HTTP=${code})"
  local task_id; task_id=$(jq -r '.metadata.annotations["infrastructure.cci.vmware.com/update-task-id"] // empty' "${resp}" 2>/dev/null)
  [[ -n "$task_id" ]] && echo "    update-task-id: ${task_id} (비동기 — 반영 후 vcfa_namespace_show_limit_cci 로 재확인)"
  rm -f "${resp}"
}

# CCI PATCH 로 storage limit 수정.
# Usage: vcfa_namespace_set_storage_limit_cci storage_limit_{mib,gib,tib}=N
vcfa_namespace_set_storage_limit_cci() {
  require_cmd jq || return 1

  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage: vcfa_namespace_set_storage_limit_cci KEY=VALUE
  storage_limit_mib=N / storage_limit_gib=N / storage_limit_tib=N
(모든 storage class 에 동일 적용)
EOF
    return 1
  fi

  local key="${VCFA_NS_NAME:-${VCFA_NS_ID:-}}"
  if [[ -z "$key" ]]; then
    echo "ERROR: VCFA_NS_NAME 필요 — vcfa_select_namespace 먼저" >&2
    return 1
  fi
  local pair; pair=$(_cci_resolve_ns "$key") || return 1
  local project="${pair%%$'\t'*}" ns_name="${pair##*$'\t'}"

  local arg="$1"; local k="${arg%%=*}" v="${arg#*=}" mult=1 vn
  case "$k" in
    storage_limit_mib) mult=1       ;;
    storage_limit_gib) mult=1024    ;;
    storage_limit_tib) mult=1048576 ;;
    *) echo "ERROR: unknown key '${k}' (storage_limit_{mib,gib,tib} 만)" >&2; return 1 ;;
  esac
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: '${k}' 값은 정수, 받은='${v}'" >&2; return 1; }
  vn=$((v*mult))
  local limit_str="${vn}Mi"

  local cur; cur=$(mktemp /tmp/cci-cur.XXXXXX)
  _cci_get_ns "$project" "$ns_name" > "${cur}" || { rm -f "${cur}"; return 1; }

  local body; body=$(mktemp /tmp/cci-pstor.XXXXXX)
  jq --arg lim "$limit_str" '
    ((.spec.classConfigOverrides.storageClasses // []) | map(.name)) as $on
    | ((.status.storageClasses // []) | map(.name)) as $sn
    | (if ($on|length) > 0 then $on else $sn end) as $names
    | {spec:{classConfigOverrides:{storageClasses:
        ($names | map({name:., limit:$lim}))
      }}}' "${cur}" > "${body}" || { rm -f "${cur}" "${body}"; return 1; }

  echo "변경 미리보기:"
  echo "  BEFORE spec : $(jq -c '.spec.classConfigOverrides.storageClasses // []' "${cur}")"
  echo "  BEFORE realized: $(jq -c '.status.storageClasses // []' "${cur}")"
  echo "  PATCH       : $(jq -c '.spec.classConfigOverrides.storageClasses' "${body}")"

  local base; base=$(_cci_base) || { rm -f "${cur}" "${body}"; return 1; }
  local resp; resp=$(mktemp /tmp/cci-pstor-resp.XXXXXX)
  local code
  code=$(curl -sk -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/merge-patch+json" \
    -H "Accept: application/json" \
    -d @"${body}" \
    -o "${resp}" -w "%{http_code}" \
    "${base}/namespaces/${project}/supervisornamespaces/${ns_name}")
  rm -f "${cur}" "${body}"

  if [[ "${code}" -lt 200 || "${code}" -ge 300 ]]; then
    echo "ERROR: CCI PATCH (storage) HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  echo "OK: PATCH accepted (HTTP=${code})"
  rm -f "${resp}"
}

vcfa_org_quota() {
  # 현재 ORG 의 VDC quota 표 + 합계.
  # 사용:
  #   vcfa_select_org && vcfa_org_quota               # 선택 후
  #   VCFA_ORG_NAME=Org1 vcfa_org_quota               # NAME 만으로 일회성 (ID 자동 조회)
  #   VCFA_ORG_ID="urn:vcloud:org:..." vcfa_org_quota # ID 직접
  _vcfa_ensure_org_id || return 1
  require_cmd jq || return 1

  local resp; resp=$(mktemp /tmp/vcfa-vdcs.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/virtualDatacenters?page=1&pageSize=128" > "${resp}" \
    || { rm -f "${resp}"; return 1; }

  echo "ORG: ${VCFA_ORG_NAME:-?} (${VCFA_ORG_ID})"

  # 매칭 VDC 개수 먼저
  local n; n=$(jq --arg id "${VCFA_ORG_ID}" '[.values[] | select(.org.id == $id)] | length' "${resp}")
  if [[ "${n}" -eq 0 ]]; then
    echo "(이 ORG 에 할당된 Virtual Data Center 없음)"
    rm -f "${resp}"
    return 0
  fi

  echo ""
  jq -r --arg id "${VCFA_ORG_ID}" '
    ["VDC", "ZONE", "CPU_LIMIT_MHz", "CPU_RSV_MHz", "MEM_LIMIT_MiB", "MEM_RSV_MiB", "STATUS"],
    (.values[]
      | select(.org.id == $id)
      | . as $vdc
      | .zoneResourceAllocation[]?
      | [$vdc.name, .zone.name,
         (.resourceAllocation.cpuLimitMHz // 0),
         (.resourceAllocation.cpuReservationMHz // 0),
         (.resourceAllocation.memoryLimitMiB // 0),
         (.resourceAllocation.memoryReservationMiB // 0),
         $vdc.status])
    | @tsv' "${resp}" \
    | column -t -s $'\t'

  echo ""
  echo "TOTAL (모든 VDC × zone 합산):"
  jq -r --arg id "${VCFA_ORG_ID}" '
    [.values[] | select(.org.id == $id) | .zoneResourceAllocation[]?.resourceAllocation]
    | "  cpu_limit_MHz = \( (map(.cpuLimitMHz // 0)        | add // 0) )\n" +
      "  cpu_rsv_MHz   = \( (map(.cpuReservationMHz // 0)  | add // 0) )\n" +
      "  mem_limit_MiB = \( (map(.memoryLimitMiB // 0)     | add // 0) )\n" +
      "  mem_rsv_MiB   = \( (map(.memoryReservationMiB // 0) | add // 0) )"
  ' "${resp}"

  rm -f "${resp}"
}

vcfa_list_orgs() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/1.0.0/orgs?page=1&pageSize=128" \
    | jq -r '
        ["NAME", "DISPLAY_NAME", "ID"],
        (.values[]? | [.name, .displayName, .id])
        | @tsv' \
    | column -t -s $'\t'
}

vcfa_select_org() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1

  local raw tmp count choice line name id
  raw=$(vcfa_api_get "https://${VCFA_FQDN}/cloudapi/1.0.0/orgs?page=1&pageSize=128") || return 1

  tmp=$(mktemp /tmp/vcfa-orgs.XXXXXX)
  echo "$raw" | jq -r '.values[]? | [.name, .displayName, .id] | @tsv' > "$tmp"
  count=$(wc -l < "$tmp")

  if [[ "$count" -eq 0 ]]; then
    echo "ERROR: no orgs returned." >&2
    rm -f "$tmp"; return 1
  fi

  echo "선택 가능한 ORG:"
  awk -F'\t' '{printf "  %2d) %-30s  %s\n", NR, $1, $2}' "$tmp"

  # bash 는 `read -rp PROMPT VAR` 지원, zsh 는 -p 가 coprocess 옵션이라 다름 → portable 형태
  printf "번호 [1-%s]: " "${count}"
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
    echo "ERROR: invalid choice." >&2
    rm -f "$tmp"; return 1
  fi

  line=$(sed -n "${choice}p" "$tmp")
  name=$(cut -f1 <<<"$line")
  id=$(cut -f3 <<<"$line")
  rm -f "$tmp"

  export VCFA_ORG_NAME="$name"
  export VCFA_ORG_ID="$id"
  _VCFA_ORG_CACHED_NAME="$name"   # 다른 함수의 NAME→ID 캐시와 일치시켜 재조회 안 일어나게
  _env_set VCFA_ORG_NAME "$name"
  _env_set VCFA_ORG_ID   "$id"

  echo ""
  echo "선택됨: VCFA_ORG_NAME=${name}  VCFA_ORG_ID=${id}"
  echo ".env 갱신 + 현재 셸 export 완료 (재source 불필요)"
}

# ============================================================
# Project helpers (tenant 모드 전용 — provider 토큰은 project-service 가 403)
# - vcfa_list_projects   : 현재 user 가 멤버인 project 목록
# - vcfa_select_project  : 대화식 선택 → VCFA_PROJECT_NAME / VCFA_PROJECT_ID 셋업 + env 저장
# ============================================================

vcfa_list_projects() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1
  local resp; resp=$(mktemp /tmp/vcfa-prj.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/project-service/api/projects?page=0&size=100" > "${resp}" \
    || { rm -f "${resp}"; return 1; }
  {
    printf 'NAME\tID\tDESCRIPTION\n'
    jq -r '.content[]? | [.name, .id, (.description // "-")] | @tsv' "${resp}"
  } | column -t -s $'\t'
  rm -f "${resp}"
}

vcfa_select_project() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  require_cmd jq || return 1
  local resp; resp=$(mktemp /tmp/vcfa-prj-sel.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/project-service/api/projects?page=0&size=100" > "${resp}" \
    || { rm -f "${resp}"; return 1; }

  local n; n=$(jq '.content | length' "${resp}")
  if [[ "$n" -eq 0 ]]; then
    echo "(접근 가능한 project 가 없습니다. provider 모드면 정상 — tenant 모드로 source 하세요.)" >&2
    rm -f "${resp}"; return 1
  fi

  echo "선택 가능한 Project:"
  jq -r '
    .content
    | to_entries[]
    | "  \(.key+1 | tostring | (" "*(2-length) + .))) \(.value.name)   (\(.value.id))   \(.value.description // "")"' "${resp}"

  printf "번호 [1-%s]: " "$n"
  local choice; read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > n )); then
    echo "ERROR: invalid choice." >&2
    rm -f "${resp}"; return 1
  fi

  local idx=$((choice-1))
  local name id
  name=$(jq -r ".content[$idx].name" "${resp}")
  id=$(jq -r ".content[$idx].id" "${resp}")
  rm -f "${resp}"

  export VCFA_PROJECT_NAME="$name"
  export VCFA_PROJECT_ID="$id"
  _env_set VCFA_PROJECT_NAME "$name"
  _env_set VCFA_PROJECT_ID   "$id"

  echo ""
  echo "선택됨: VCFA_PROJECT_NAME=${name}  VCFA_PROJECT_ID=${id}"
  echo "${VCFA_ENV_FILE:-.env} 갱신 + 현재 셸 export 완료"
}
