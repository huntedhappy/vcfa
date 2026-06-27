#!/usr/bin/env bash
# ============================================================
# VCFA 기본 인프라 자동화 헬퍼 (순차 셋업용)
#   vcfa_list_content_libraries                              - 콘텐츠 라이브러리 목록
#   vcfa_create_content_library <name> [storageClass] [desc] - 로컬 콘텐츠 라이브러리 생성(멱등)
#
# 의존: vcfa-api-lib.sh (login_vcfa / vcfa_api_get / _vcfa_wait_task / require_cmd)
#       → 보통 `source scripts/session.sh .env` 로 한꺼번에 로드됨.
# 세션: 콘텐츠 라이브러리는 **provider** API(cloudapi/v1/contentLibraries) → provider 세션 필요
#       (`.env`, VCFA_TENANT_ORG 없이). tenant 세션이면 403 가능.
# 용도: VM 이미지용 라이브러리(예: "vcfa vm images")를 만든 뒤, 표준 cloud 이미지(OVA)를
#       업로드 → Supervisor 자동연결(autoAttach) → getVMImage 가 노출.
# ============================================================

: "${VCFA_API_VERSION:=9.1.0}"

# 콘텐츠 라이브러리 목록 (name / type / subscribed / id)
vcfa_list_content_libraries() {
  require_cmd jq || return 1
  [[ -n "${TOKEN:-}" ]] || login_vcfa || return 1
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/contentLibraries?page=1&pageSize=128" \
    | jq -r '
        ["NAME","TYPE","SUBSCRIBED","ID"],
        (.values[]? | [ .name, (.libraryType // "-"), (.isSubscribed|tostring), .id ])
        | @tsv' \
    | column -t -s $'\t'
}

# 이름으로 라이브러리 id 조회 (없으면 빈 출력)
vcfa_content_library_id() {
  local name="${1:?Usage: vcfa_content_library_id <name>}"
  require_cmd jq || return 1
  [[ -n "${TOKEN:-}" ]] || login_vcfa || return 1
  vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/contentLibraries?page=1&pageSize=128" 2>/dev/null \
    | jq -r --arg n "$name" 'first(.values[]? | select(.name==$n) | .id) // empty'
}

# 로컬 콘텐츠 라이브러리 생성 (멱등 — 동명 있으면 생성 생략).
# Usage: vcfa_create_content_library <name> [storageClass(name|urn)] [description]
#   storageClass 미지정 → /cloudapi/v1/storageClasses 의 첫 항목 사용.
#   성공 시 전역 VCFA_CONTENT_LIBRARY_ID 에 id 를 export(다음 단계에서 사용).
vcfa_create_content_library() {
  local name="${1:?Usage: vcfa_create_content_library <name> [storageClass] [description]}"
  local sc_in="${2:-}"
  local desc="${3:-}"
  require_cmd jq || return 1
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN 미설정}"
  [[ -n "${TOKEN:-}" ]] || login_vcfa || return 1

  local base="https://${VCFA_FQDN}/cloudapi/v1/contentLibraries"

  # 0) 멱등: 동명 라이브러리 있으면 생략
  local existing
  existing=$(vcfa_content_library_id "$name" 2>/dev/null)
  if [[ -n "$existing" ]]; then
    echo "콘텐츠 라이브러리 '${name}' 이미 존재 — 생성 생략 (id=${existing})"
    export VCFA_CONTENT_LIBRARY_ID="$existing"
    return 0
  fi

  # 1) storageClass id 결정 (urn 직접 / 이름 매치 / 첫 항목)
  local sc_id="" sc_name="" sc_json
  if [[ "$sc_in" == urn:vcloud:storageClass:* ]]; then
    sc_id="$sc_in"
  else
    sc_json=$(vcfa_api_get "https://${VCFA_FQDN}/cloudapi/v1/storageClasses?page=1&pageSize=128" 2>/dev/null)
    if [[ -n "$sc_in" ]]; then
      sc_id=$(echo "$sc_json" | jq -r --arg n "$sc_in" 'first(.values[]? | select(.name==$n) | .id) // empty')
    else
      sc_id=$(echo "$sc_json" | jq -r '.values[0]?.id // empty')
    fi
    sc_name=$(echo "$sc_json" | jq -r --arg id "$sc_id" 'first(.values[]? | select(.id==$id) | .name) // empty')
  fi
  if [[ -z "$sc_id" ]]; then
    echo "ERROR: storageClass 를 못 찾음 (입력='${sc_in:-（미지정）}'). 'vcfa_api_get .../cloudapi/v1/storageClasses' 로 확인." >&2
    return 1
  fi
  echo "storageClass = ${sc_name:-$sc_id} (${sc_id})"

  # 2) POST body
  local body_file
  body_file=$(mktemp /tmp/vcfa-cl-body.XXXXXX)
  jq -n --arg name "$name" --arg desc "$desc" --arg sc "$sc_id" \
    '{name:$name, description:$desc, isSubscribed:false, autoAttach:true, storageClasses:[{id:$sc}]}' \
    > "$body_file"

  # 3) POST → 202 + Location task 폴링
  local hdr resp code
  hdr=$(mktemp /tmp/vcfa-cl-hdr.XXXXXX); resp=$(mktemp /tmp/vcfa-cl-resp.XXXXXX)
  code=$(curl -sk -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json;version=${VCFA_API_VERSION}" \
    -H "Content-Type: application/json;version=${VCFA_API_VERSION}" \
    -d @"${body_file}" -D "${hdr}" -o "${resp}" -w "%{http_code}" "${base}")
  rm -f "${body_file}"
  if [[ "${code}" -lt 200 || "${code}" -ge 300 ]]; then
    echo "ERROR: 라이브러리 생성 실패 HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${hdr}" "${resp}"; return 1
  fi
  echo "POST accepted (HTTP=${code})"
  if [[ "${code}" == "202" ]]; then
    local task_url
    task_url=$(awk -F': ' 'tolower($1)=="location"{print $2}' "${hdr}" | tr -d '\r')
    if [[ -n "${task_url}" ]]; then
      _vcfa_wait_task "${task_url}" 300 || { rm -f "${hdr}" "${resp}"; return 1; }
    fi
  fi
  rm -f "${hdr}" "${resp}"

  # 4) 생성 확인 + id export
  local new_id
  new_id=$(vcfa_content_library_id "$name" 2>/dev/null)
  if [[ -z "${new_id}" ]]; then
    echo "WARN: 생성은 됐으나 id 재조회 실패 — 목록을 확인하세요." >&2
    return 1
  fi
  export VCFA_CONTENT_LIBRARY_ID="${new_id}"
  echo "OK: 콘텐츠 라이브러리 생성됨 '${name}' (id=${new_id})"
  echo "  → 다음: 이 라이브러리에 표준 cloud 이미지(OVA)를 업로드(UI/ovftool) → getVMImage 노출"
}
