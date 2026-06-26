# ============================================================
# Cloud Assembly content (blueprint / form / package) — 로컬 + REST 헬퍼
#
# 로컬 (offline, 모든 모드에서 작동):
#   bp_list / bp_check [FILE] / bp_show FILE          - blueprint YAML 검증/요약
#   form_list / form_check [FILE] / form_show FILE    - form YAML 검증/요약
#   pkg_list / pkg_check [FILE] / pkg_show FILE       - .package ZIP 검증/요약
#   content_pairs                                      - blueprint ↔ form 매칭표 추측
#
# REST (tenant 모드 전용 — source scripts/session.sh .env.tenant 후 사용):
#   bp_remote_list                                     - 서버 blueprint 목록
#   bp_remote_get <id>                                 - 단건 조회
#   bp_remote_import <yaml> [name]                     - DRAFT 생성
#   bp_remote_release <id> [version] [desc]            - 새 version + catalog 노출
#   bp_remote_export <id> [out-file]                   - 서버 → 로컬 YAML
#   bp_remote_delete <id>                              - 삭제 (catalog item 도 자동 정리)
#   catalog_remote_list                                - 카탈로그 item 목록 (form 의 sourceId)
#   form_remote_import <form-yml> <catalog-item-id>    - form 적용
#   form_remote_delete <form-id>                       - 삭제
#
# REST 자동화 전제: VCFA_TENANT_ORG 가 설정된 .env.tenant 로 source, 그리고
# 그 user 가 target project 의 멤버여야 함 (provider 토큰은 403/500).
# 검증 완료 2026-05-24: configadmin@ProviderConsumptionOrg + default-project.
# ============================================================

# 루트 디렉터리 (이 lib 위치 기준 한 단계 위)
_content_root() {
  # lib 파일 위치 — session.sh 가 source 시 _VCFA_LIB_DIR 설정. 없으면 fallback
  local d="${_VCFA_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
  (cd "${d}/.." && pwd)
}

# 내부: 단일 파일 YAML 문법 검증 (yq 사용). stdout 무음, return 0/1
_yaml_lint() {
  local f="$1"
  yq eval '.' "$f" >/dev/null 2>&1
}

# 내부: 친근한 size 표시
_human_size() {
  local b="$1"
  if   (( b >= 1048576 )); then printf '%.1fM' "$(echo "scale=1; $b/1048576" | bc)"
  elif (( b >= 1024 )); then    printf '%.1fK' "$(echo "scale=1; $b/1024" | bc)"
  else                          printf '%dB' "$b"
  fi
}

bp_list() {
  require_cmd yq || return 1
  local root; root=$(_content_root)
  local dir="${root}/blueprints"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: ${dir} 디렉터리가 없습니다." >&2
    return 1
  fi

  {
    printf 'FILE\tFORMAT\tINPUTS\tRESOURCES\tSIZE\n'
    local f rel fmt ins res sz
    while IFS= read -r f; do
      rel="${f#${root}/}"
      fmt=$(yq eval '.formatVersion // "?"' "$f" 2>/dev/null)
      ins=$(yq eval '.inputs | length // 0' "$f" 2>/dev/null)
      res=$(yq eval '.resources | length // 0' "$f" 2>/dev/null)
      sz=$(_human_size "$(wc -c < "$f")")
      printf '%s\t%s\t%s\t%s\t%s\n' "${rel}" "${fmt}" "${ins}" "${res}" "${sz}"
    done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
  } | column -t -s $'\t'
}

bp_check() {
  require_cmd yq || return 1
  local root; root=$(_content_root)
  local dir="${root}/blueprints"
  local f rc=0 st fmt has_inputs has_resources

  local files=()
  if [[ -n "$1" ]]; then
    files=("$1")
  else
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
  fi

  for f in "${files[@]}"; do
    local issues=()

    # 1) YAML 문법
    if ! _yaml_lint "$f"; then
      issues+=("YAML syntax error")
    else
      # 2) 필수 키 — Cloud Assembly Cloud Template 의 최소 형식
      fmt=$(yq eval '.formatVersion' "$f" 2>/dev/null)
      [[ "$fmt" == "1" ]] || issues+=("formatVersion != 1 (got: ${fmt:-null})")
      has_inputs=$(yq eval 'has("inputs")' "$f" 2>/dev/null)
      has_resources=$(yq eval 'has("resources")' "$f" 2>/dev/null)
      [[ "$has_resources" == "true" ]] || issues+=("missing .resources")
      # inputs 는 선택적 — 경고만 (별도 표시 X)
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
      st="OK"
    else
      st="FAIL: $(IFS='; '; echo "${issues[*]}")"
      rc=1
    fi
    printf '%s\t%s\n' "${f#${root}/}" "$st"
  done | column -t -s $'\t'
  return $rc
}

bp_show() {
  local f="${1:?Usage: bp_show <blueprint-file>}"
  [[ -f "$f" ]] || { echo "ERROR: file not found: $f" >&2; return 1; }
  require_cmd yq || return 1
  echo "=== ${f} ==="
  yq eval '{
    "formatVersion": .formatVersion,
    "inputs": (.inputs // {} | to_entries | map({"key": .key, "type": .value.type, "default": .value.default, "from-vRO": (.value["$data"] // null) })),
    "resources": (.resources // {} | to_entries | map({"key": .key, "type": .value.type}))
  }' "$f"
}

form_list() {
  require_cmd yq || return 1
  local root; root=$(_content_root)
  local dir="${root}/forms"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: ${dir} 디렉터리가 없습니다." >&2
    return 1
  fi

  {
    printf 'FILE\tPAGES\tFIELDS\tSIZE\n'
    local f rel pages fields sz
    while IFS= read -r f; do
      rel="${f#${root}/}"
      pages=$(yq eval '.layout.pages | length // 0' "$f" 2>/dev/null)
      fields=$(yq eval '[.layout.pages[]?.sections[]?.fields[]?] | length // 0' "$f" 2>/dev/null)
      sz=$(_human_size "$(wc -c < "$f")")
      printf '%s\t%s\t%s\t%s\n' "${rel}" "${pages}" "${fields}" "${sz}"
    done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
  } | column -t -s $'\t'
}

form_check() {
  require_cmd yq || return 1
  local root; root=$(_content_root)
  local dir="${root}/forms"
  local f rc=0 st has_layout pages_count

  local files=()
  if [[ -n "$1" ]]; then
    files=("$1")
  else
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort)
  fi

  for f in "${files[@]}"; do
    local issues=()

    if ! _yaml_lint "$f"; then
      issues+=("YAML syntax error")
    else
      # Service Broker Custom Form: 최소 .layout.pages[] 존재
      has_layout=$(yq eval 'has("layout")' "$f" 2>/dev/null)
      [[ "$has_layout" == "true" ]] || issues+=("missing .layout")
      pages_count=$(yq eval '.layout.pages | length // 0' "$f" 2>/dev/null)
      (( pages_count > 0 )) || issues+=(".layout.pages 비어있음")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
      st="OK"
    else
      st="FAIL: $(IFS='; '; echo "${issues[*]}")"
      rc=1
    fi
    printf '%s\t%s\n' "${f#${root}/}" "$st"
  done | column -t -s $'\t'
  return $rc
}

form_show() {
  local f="${1:?Usage: form_show <form-file>}"
  [[ -f "$f" ]] || { echo "ERROR: file not found: $f" >&2; return 1; }
  require_cmd yq || return 1
  echo "=== ${f} ==="
  yq eval '{
    "pages": [.layout.pages[]? | {
      "id": .id,
      "sections": [.sections[]? | {
        "id": .id,
        "fields": [.fields[]? | {"id": .id, "display": .display}]
      }]
    }]
  }' "$f"
}

pkg_list() {
  require_cmd unzip || return 1
  local root; root=$(_content_root)
  local dir="${root}/packages"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: ${dir} 디렉터리가 없습니다." >&2
    return 1
  fi

  {
    printf 'FILE\tELEMENTS\tSIGNED\tSIZE\n'
    local f rel elements signed sz
    while IFS= read -r f; do
      rel="${f#${root}/}"
      elements=$(unzip -l "$f" 2>/dev/null | awk '$NF ~ /^elements\// && $NF ~ /\/data$/ {n++} END{print n+0}')
      if unzip -l "$f" 2>/dev/null | grep -q "^.*signatures/dunes-meta-inf$"; then signed=yes; else signed=no; fi
      sz=$(_human_size "$(wc -c < "$f")")
      printf '%s\t%s\t%s\t%s\n' "${rel}" "${elements}" "${signed}" "${sz}"
    done < <(find "$dir" -maxdepth 2 -type f -name "*.package" | sort)
  } | column -t -s $'\t'
}

pkg_check() {
  require_cmd unzip || return 1
  local root; root=$(_content_root)
  local dir="${root}/packages"
  local f rc=0 st listing n

  local files=()
  if [[ -n "$1" ]]; then
    files=("$1")
  else
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -maxdepth 2 -type f -name "*.package" | sort)
  fi

  for f in "${files[@]}"; do
    local issues=()
    if ! listing=$(unzip -l "$f" 2>&1); then
      issues+=("not a valid ZIP")
    else
      # dunes-meta-inf 존재
      echo "$listing" | grep -q "dunes-meta-inf$" || issues+=("missing dunes-meta-inf")
      # 최소 element 1개
      n=$(echo "$listing" | awk '$NF ~ /^elements\// && $NF ~ /\/data$/ {n++} END{print n+0}')
      (( n > 0 )) || issues+=("no elements")
      # 서명 디렉터리
      echo "$listing" | grep -q "^.*signatures/" || issues+=("no signatures/ dir (unsigned)")
      # 인증서
      echo "$listing" | grep -q "^.*certificates/" || issues+=("no certificates/ dir")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
      st="OK"
    else
      st="FAIL: $(IFS='; '; echo "${issues[*]}")"
      rc=1
    fi
    printf '%s\t%s\n' "${f#${root}/}" "$st"
  done | column -t -s $'\t'
  return $rc
}

pkg_show() {
  # Usage: pkg_show <package-file>
  # 메타(이름/서명자/버전) + element 목록 (name, type, module, result-type, inputs)
  local f="${1:?Usage: pkg_show <package-file>}"
  [[ -f "$f" ]] || { echo "ERROR: file not found: $f" >&2; return 1; }
  require_cmd unzip || return 1
  require_cmd iconv || return 1

  echo "=== ${f} ==="
  echo ""
  echo "[메타데이터 — dunes-meta-inf]"
  unzip -p "$f" dunes-meta-inf 2>/dev/null \
    | grep -oE '<entry key="[^"]+">[^<]+</entry>' \
    | sed -E 's|<entry key="([^"]+)">([^<]+)</entry>|  \1 = \2|'

  echo ""
  echo "[Element 목록]"
  # 각 element 의 data/info/categories 를 tmpfile 로 추출해서 처리.
  # ※ local var=$(unzip|iconv ...) 식 명령 치환은 zsh 에서 UTF-16/BOM 같은 특수바이트가
  #   섞이면 변수 선언 자체를 'typeset -p' 형식으로 stdout 에 흘리는 버그가 있어 회피.
  local data_f info_f cat_f
  data_f=$(mktemp /tmp/pkg-data.XXXXXX)
  info_f=$(mktemp /tmp/pkg-info.XXXXXX)
  cat_f=$(mktemp /tmp/pkg-cat.XXXXXX)

  {
    printf 'NAME\tTYPE\tMODULE\tRESULT-TYPE\tINPUTS\n'
    local eid name elem_type module result_type inputs
    while IFS= read -r eid; do
      unzip -p "$f" "elements/${eid}/info" 2>/dev/null > "$info_f"
      unzip -p "$f" "elements/${eid}/categories" 2>/dev/null | iconv -f UTF-16 -t UTF-8 2>/dev/null > "$cat_f"
      unzip -p "$f" "elements/${eid}/data"       2>/dev/null | iconv -f UTF-16 -t UTF-8 2>/dev/null > "$data_f"

      elem_type=$(grep -oE '<entry key="type">[^<]+</entry>' "$info_f" \
        | sed -E 's|.*>([^<]+)<.*|\1|')
      module=$(grep -oE "<category name='[^']+'" "$cat_f" \
        | head -1 | sed "s/<category name='\\([^']*\\)'/\\1/")
      name=$(grep -oE 'dunes-script-module name="[^"]+"' "$data_f" \
        | head -1 | sed 's/.*name="\([^"]*\)".*/\1/')
      result_type=$(grep -oE 'result-type="[^"]+"' "$data_f" \
        | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
      inputs=$(grep -cE '<param n="[^"]+"' "$data_f")

      printf '%s\t%s\t%s\t%s\t%s\n' "${name:-?}" "${elem_type:-?}" "${module:-?}" "${result_type:-?}" "${inputs:-0}"
    done < <(unzip -l "$f" 2>/dev/null | awk '$NF ~ /^elements\/[^\/]+\/data$/ {print $NF}' | sed -E 's|elements/([^/]+)/data|\1|' | sort -u)
  } | column -t -s $'\t'

  rm -f "$data_f" "$info_f" "$cat_f"
}

content_pairs() {
  # blueprint ↔ form 매칭 추측 — 파일 이름의 공통 어휘 기반.
  # blueprint_vm.yaml ↔ custom_vm.yml, blueprint_vra_cluster.yaml ↔ custom_cluster.yml 등.
  # 정확한 매칭표는 운영자가 별도 관리 (각 README 의 매칭표 참조).
  local root; root=$(_content_root)
  echo "(파일명에서 'blueprint_' / 'custom_' / 'vra_' / 'vcfa_' 접두/접미 제거 후 비교)"
  echo ""
  printf '%s\n' "BLUEPRINT	FORM	MATCHED_KEY"

  local bp_dir="${root}/blueprints" form_dir="${root}/forms"
  local f rel key form_rel matched fkey
  while IFS= read -r f; do
    rel="${f#${root}/}"
    # archive/ 는 표시만 하고 매칭 시도 안함
    if [[ "$rel" == */archive/* ]]; then
      printf '%s\t%s\t%s\n' "$rel" "-" "(archive)"
      continue
    fi
    # 키 추출 — 접두사들을 반복적으로 제거 (blueprint_vra_cluster → vra_cluster → cluster)
    key=$(basename "$f" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
    # forms/ 안에 동일 키 매칭
    matched=""
    while IFS= read -r form_rel; do
      fkey=$(basename "$form_rel" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
      if [[ "$fkey" == "$key" ]]; then
        matched="${form_rel#${root}/}"
        break
      fi
    done < <(find "$form_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/archive/*" | sort)
    printf '%s\t%s\t%s\n' "$rel" "${matched:-(no match)}" "$key"
  done < <(find "$bp_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) | sort) | column -t -s $'\t'
}

# ============================================================
# Blueprint / Form REST 자동화 (tenant 모드 전용)
#
# 전제: source scripts/session.sh .env.tenant 후 사용. 즉
#       - TOKEN, VCFA_FQDN, VCFA_PROJECT_ID 가 설정되어 있어야 함
#       - configadmin 같이 project 멤버인 user 의 token 이어야 200
#
# 검증된 흐름 (2026-05-24):
#   1) bp_remote_import <yaml> [name]   → blueprint 생성 (DRAFT)
#   2) bp_remote_release <id>            → 새 version + release → catalog item 자동 생성
#   3) form_remote_import <yml> <catalog-item-id>  → 그 item 에 form 적용
# 삭제는 form 먼저, blueprint 가 나중 (역순). blueprint 삭제 시 catalog item 도 자동 정리.
# ============================================================

_remote_guard() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  : "${TOKEN:?ERROR: TOKEN 이 없음 — source scripts/session.sh .env.tenant 먼저}"
  if [[ -z "${VCFA_TENANT_ORG:-}" ]]; then
    echo "WARN: tenant 모드가 아닌 듯 (VCFA_TENANT_ORG 미설정). REST 호출은 403/500 가능성." >&2
  fi
  require_cmd jq || return 1
  return 0
}

_project_id() {
  if [[ -n "${VCFA_PROJECT_ID:-}" ]]; then
    echo "${VCFA_PROJECT_ID}"
    return 0
  fi
  echo "ERROR: VCFA_PROJECT_ID 가 없음 — vcfa_select_project 로 먼저 선택" >&2
  return 1
}

# ---- Blueprint ----

bp_remote_list() {
  _remote_guard || return 1
  local resp; resp=$(mktemp /tmp/bp-list.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" > "${resp}" \
    || { rm -f "${resp}"; return 1; }
  {
    printf 'NAME\tID\tPROJECT\tSTATUS\tVALID\tUPDATED\n'
    jq -r '.content[]? | [.name, .id, .projectName, (.status // "?"), (.valid // "?" | tostring), (.updatedAt // .createdAt // "")] | @tsv' "${resp}"
  } | column -t -s $'\t'
  rm -f "${resp}"
}

bp_remote_get() {
  local id="${1:?Usage: bp_remote_get <blueprint-id>}"
  _remote_guard || return 1
  vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}" \
    | jq '{id, name, projectId, projectName, status, valid, errors, createdAt, updatedAt, "content_preview": (.content // "" | .[0:200])}'
}

bp_remote_import() {
  # Usage: bp_remote_import <yaml-file> [name]
  # name 기본: <yaml-basename> (확장자 제외)
  local f="${1:?Usage: bp_remote_import <yaml-file> [name]}"
  [[ -f "$f" ]] || { echo "ERROR: file not found: $f" >&2; return 1; }
  _remote_guard || return 1
  local pid; pid=$(_project_id) || return 1

  local name="${2:-$(basename "$f" | sed -E 's/\.(yaml|yml)$//; s/^blueprint_//')}"

  # 같은 이름의 blueprint 가 이미 있으면 새로 만들지 않고 update.
  # blueprint name 은 unique 가 아니라서, 무조건 POST 하면 실행할 때마다 동일 이름이 중복 생성됨.
  # → 목록 조회 후 같은 이름이 있으면 그 id 로 PUT(update). 같은 project 우선, 여러 개면 최신 것.
  local existing; existing=$(mktemp /tmp/bp-find.XXXXXX)
  local existing_id="" n_match=0 sameproj_ids=""
  if vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" > "${existing}" 2>/dev/null; then
    n_match=$(jq --arg name "$name" '[.content[]? | select(.name == $name)] | length' "${existing}")
    existing_id=$(jq -r --arg name "$name" --arg pid "$pid" '
      [.content[]? | select(.name == $name)] as $byname
      | (($byname | map(select(.projectId == $pid))) | if length > 0 then . else $byname end)
      | sort_by(.updatedAt // .createdAt // "") | last | .id // ""
    ' "${existing}")
    sameproj_ids=$(jq -r --arg name "$name" --arg pid "$pid" '[.content[]? | select(.name==$name and .projectId==$pid) | .id] | .[]' "${existing}" 2>/dev/null)
  fi
  rm -f "${existing}"
  if [[ "${n_match:-0}" -gt 1 ]]; then
    echo "WARN: 이름 '${name}' blueprint 가 ${n_match} 개 존재 → 가장 최근(${existing_id}) 갱신. 나머지 중복은 'bp_remote_delete <id>' 로 정리하세요." >&2
  fi

  # ★ recreate: VCFA_BP_RECREATE=1 이면 동명(현재 project) blueprint 를 삭제하고 새로 생성(fresh $data 인덱스).
  #   update(PUT)는 인덱스를 새로 안 만들어 드롭다운이 stale → delete+create 로 확실히 새로 만든다.
  #   (다른 project 의 동명 blueprint 는 건드리지 않고, 항상 현재 project 에 새로 POST 한다)
  if [[ "${VCFA_BP_RECREATE:-0}" == "1" ]]; then
    if [[ -n "$sameproj_ids" ]]; then
      echo "VCFA_BP_RECREATE=1 — 동명 '${name}' (현재 project) 삭제 후 재생성:"
      local _did
      for _did in $sameproj_ids; do
        printf '  - 삭제 %s ... ' "$_did"
        if bp_remote_delete "$_did" >/dev/null 2>&1; then echo "OK"; else echo "실패(수동 확인 필요)"; fi
      done
    fi
    existing_id=""   # 강제 POST(create)
  fi

  # ★ fresh 강제: VCFA_BP_CREATE_ONLY=1 이면 동명 blueprint 가 있을 때 PUT(update) 대신 에러.
  #   update 는 $data 인덱스를 새로 안 만들어 드롭다운이 stale 상태로 남음(클린 재업로드의 핵심 함정).
  #   주의: 이름 매칭은 *모든 project 횡단* — 다른 project 에 남은 동명 blueprint 도 걸림. (recreate 모드면 위에서 처리됨)
  if [[ "${VCFA_BP_CREATE_ONLY:-0}" == "1" && -n "$existing_id" ]]; then
    echo "ERROR: VCFA_BP_CREATE_ONLY=1 인데 이름 '${name}' blueprint 가 이미 존재(id=${existing_id})." >&2
    echo "  기존을 먼저 삭제(bp_remote_delete ${existing_id})하거나, VCFA_BP_RECREATE=1 로 자동 삭제+재생성 하세요." >&2
    echo "  (모든 project 횡단 검색이라 다른 project 에 남아 있어도 매칭됩니다.)" >&2
    return 1
  fi

  # YAML → JSON-safe 문자열
  local content_str; content_str=$(jq -Rs '.' < "$f")
  local body; body=$(mktemp /tmp/bp-import.XXXXXX)
  jq -n --arg name "$name" --arg pid "$pid" --argjson content "$content_str" \
    '{name:$name, projectId:$pid, content:$content}' > "$body"

  # 있으면 PUT(update, 200), 없으면 POST(create, 201)
  local method url okcode action
  if [[ -n "$existing_id" ]]; then
    method=PUT;  url="https://${VCFA_FQDN}/blueprint/api/blueprints/${existing_id}"; okcode=200; action=updated
  else
    method=POST; url="https://${VCFA_FQDN}/blueprint/api/blueprints";                okcode=201; action=created
  fi

  local resp; resp=$(mktemp /tmp/bp-import-resp.XXXXXX)
  local code
  code=$(curl -sk -X "${method}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d @"${body}" \
    -o "${resp}" -w "%{http_code}" \
    "${url}")
  rm -f "${body}"

  if [[ "${code}" != "${okcode}" ]]; then
    echo "ERROR: blueprint ${action} HTTP=${code} (${method})" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  local id; id=$(jq -r '.id // empty' "${resp}")
  [[ -z "$id" ]] && id="$existing_id"
  local valid; valid=$(jq -r '.valid // "?"' "${resp}")
  rm -f "${resp}"

  # 다음 단계가 사용할 수 있도록 셸 환경에 export — 손으로 id 복사 안 해도 됨.
  export VCFA_BP_ID="$id"
  export VCFA_BP_NAME="$name"
  echo "OK: blueprint ${action}"
  echo "    name = ${name}"
  echo "    id   = ${id}    (셸에 VCFA_BP_ID 로 export 됨)"
  echo "    valid=${valid}, status=DRAFT"
  echo "    다음 단계: bp_remote_release                 (인자 생략 = 방금 import 한 것)"
}

bp_remote_release() {
  # Usage: bp_remote_release [blueprint-id] [version] [description]
  # blueprint-id 생략 시 VCFA_BP_ID (이전에 import 한 것) 사용.
  # version 기본: v<YYYYMMDD>.<HHMMSS>
  local id="${1:-${VCFA_BP_ID:-}}"
  if [[ -z "$id" ]]; then
    echo "ERROR: blueprint-id 필요. 인자로 주거나, bp_remote_import 직후 호출 (VCFA_BP_ID 가 자동 세팅됨)" >&2
    return 1
  fi
  local version="${2:-v$(date +%Y%m%d.%H%M%S)}"
  local desc="${3:-automated release}"
  _remote_guard || return 1

  local body; body=$(mktemp /tmp/bp-rel.XXXXXX)
  jq -n --arg v "$version" --arg d "$desc" \
    '{version:$v, description:$d, changeLog:"", release:true}' > "$body"

  local resp; resp=$(mktemp /tmp/bp-rel-resp.XXXXXX)
  local code
  code=$(curl -sk -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d @"${body}" \
    -o "${resp}" -w "%{http_code}" \
    "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}/versions")
  rm -f "${body}"

  if [[ "${code}" != "201" ]]; then
    echo "ERROR: blueprint release HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  local st; st=$(jq -r '.status' "${resp}")
  rm -f "${resp}"
  echo "OK: released"
  echo "    bp     = ${id}"
  echo "    version= ${version}"
  echo "    status = ${st}"

  # catalog item id 자동 추출 → 다음 단계 (form_remote_import) 가 사용
  echo "    (catalog 반영 대기...)"
  local tries=0 item_id="" item_name=""
  while (( tries < 10 )); do
    sleep 1
    item_id=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
      "https://${VCFA_FQDN}/catalog/api/items?page=0&size=200" \
      | jq -r --arg n "${VCFA_BP_NAME:-}" '
          if $n != ""
          then (.content[]? | select(.name == $n) | .id)
          else .content[0].id // empty
          end' | head -1)
    if [[ -n "$item_id" && "$item_id" != "null" ]]; then
      break
    fi
    ((tries++))
  done

  if [[ -n "$item_id" && "$item_id" != "null" ]]; then
    item_name=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
      "https://${VCFA_FQDN}/catalog/api/items/${item_id}" 2>/dev/null | jq -r '.name // ""')
    export VCFA_CATALOG_ITEM_ID="$item_id"
    echo "    catalog: ${item_name:-?}  item_id=${item_id}    (셸에 VCFA_CATALOG_ITEM_ID export)"
    echo "    다음 단계: form_remote_import <form.yml>     (인자 생략된 sourceId 는 자동 사용)"
  else
    echo "    경고: catalog item 을 찾지 못함. 잠시 후 catalog_remote_list 로 직접 확인" >&2
  fi
}

bp_remote_delete() {
  local id="${1:?Usage: bp_remote_delete <blueprint-id>}"
  _remote_guard || return 1
  local code
  code=$(curl -sk -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o /dev/null -w "%{http_code}" \
    "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}")
  if [[ "${code}" == "204" ]]; then
    echo "OK: blueprint deleted — id=${id}"
  else
    echo "ERROR: delete HTTP=${code}" >&2; return 1
  fi
}

bp_remote_export() {
  # Usage: bp_remote_export <blueprint-id> [out-file|sub-dir]
  #   <blueprint-id>      : 필수
  #   2번째 인자 종류:
  #     - / 로 끝나거나 디렉터리면 → sub-dir 로 간주 → 파일명은 blueprint_<name>.yaml 자동 생성
  #     - 그 외 → 지정 파일 경로로 저장
  #     - 생략 → blueprints/exported/blueprint_<name>.yaml
  local id="${1:?Usage: bp_remote_export <blueprint-id> [out-file|sub-dir]}"
  local hint="${2:-}"
  _remote_guard || return 1
  local resp; resp=$(mktemp /tmp/bp-exp.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}" > "${resp}" \
    || { rm -f "${resp}"; return 1; }

  local name; name=$(jq -r '.name' "${resp}")
  local out
  if [[ -z "$hint" ]]; then
    out="blueprints/exported/blueprint_${name}.yaml"
  elif [[ "$hint" == */ ]] || [[ -d "$hint" ]] || [[ "$hint" =~ ^(blueprints|forms)/[^/]+$ ]]; then
    # sub-dir 로 취급
    local dir="${hint%/}"
    [[ "$dir" = /* ]] || dir="${dir}"   # 상대경로 그대로
    out="${dir}/blueprint_${name}.yaml"
  else
    out="$hint"
  fi
  mkdir -p "$(dirname "$out")"
  jq -r '.content' "${resp}" > "$out"
  echo "OK: exported — id=${id}  name=${name}  → ${out}"
  ls -la "$out"
  rm -f "${resp}"
}

# 대화식 — 서버 blueprint 목록 → 번호 선택 → 다운로드.
# Usage: bp_select_export [sub-dir]
#   sub-dir 미지정 시 기본 blueprints/exported/
bp_select_export() {
  _remote_guard || return 1
  local sub="${1:-blueprints/exported}"

  local resp; resp=$(mktemp /tmp/bp-sel.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" > "${resp}" \
    || { rm -f "${resp}"; return 1; }

  local n; n=$(jq '.content | length' "${resp}")
  if [[ "$n" -eq 0 ]]; then
    echo "(서버에 blueprint 가 없음)"; rm -f "${resp}"; return 1
  fi

  echo "선택 가능한 Blueprint (${n}개):"
  jq -r '.content | to_entries[] | "  \(.key+1 | tostring | (" "*(2-length) + .))) \(.value.name)   [\(.value.status)]   id=\(.value.id)"' "${resp}"
  echo ""
  echo "저장 위치: ${sub}/blueprint_<name>.yaml"
  printf "번호 [1-%s] (q=취소): " "$n"
  local choice; _vcfa_read_line choice
  if [[ "$choice" == "q" ]]; then echo "취소"; rm -f "${resp}"; return 1; fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > n )); then
    echo "ERROR: invalid choice." >&2; rm -f "${resp}"; return 1
  fi
  local idx=$((choice-1))
  local id; id=$(jq -r ".content[$idx].id" "${resp}")
  rm -f "${resp}"

  bp_remote_export "$id" "${sub}/"
}

# ---- Catalog ----

catalog_remote_list() {
  _remote_guard || return 1
  local resp; resp=$(mktemp /tmp/cat.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/catalog/api/items?page=0&size=200" > "${resp}" \
    || { rm -f "${resp}"; return 1; }
  {
    printf 'NAME\tITEM_ID\tTYPE\n'
    jq -r '.content[]? | [.name, .id, (.type.id // .type // "?")] | @tsv' "${resp}"
  } | column -t -s $'\t'
  rm -f "${resp}"
}

# ---- Form ----

form_remote_import() {
  # Usage: form_remote_import <form-file> [catalog-item-id]
  # catalog-item-id 생략 시 VCFA_CATALOG_ITEM_ID (이전 release 의 자동 산출) 사용.
  local f="${1:?Usage: form_remote_import <form-file> [catalog-item-id]}"
  local src="${2:-${VCFA_CATALOG_ITEM_ID:-}}"
  if [[ -z "$src" ]]; then
    echo "ERROR: catalog-item-id 필요. 인자로 주거나, bp_remote_release 직후 호출 (VCFA_CATALOG_ITEM_ID 자동 세팅)" >&2
    return 1
  fi
  [[ -f "$f" ]] || { echo "ERROR: file not found: $f" >&2; return 1; }
  _remote_guard || return 1

  # ★ 같은 catalog item 에 기존 폼이 있으면 POST 는 *교체하지 않고 무시*함(201 OK 줘도 옛 폼 유지).
  #   → 재import 가 반영되려면 기존 폼을 먼저 삭제해야 함.
  local _existing
  _existing=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "https://${VCFA_FQDN}/form-service/api/forms/fetchBySourceAndType?formType=requestForm&sourceId=${src}&sourceType=com.vmw.blueprint" \
    | jq -r '.id // empty' 2>/dev/null)
  if [[ -n "$_existing" ]]; then
    echo "  기존 폼 삭제(교체): ${_existing}"
    curl -sk -X DELETE -H "Authorization: Bearer ${TOKEN}" \
      "https://${VCFA_FQDN}/form-service/api/forms/${_existing}" >/dev/null 2>&1
  fi

  # ★ 방어: layout 의 signpostPosition 키는 이 빌드에서 드롭다운 렌더링을 깨뜨림(무한 로딩).
  #   stale 폼 파일에 남아 있어도 전송 직전 재귀 제거. (schema 의 signpost: 는 유지)
  #   strip 위해 JSON 으로 정규화 후 formFormat=JSON 으로 전송 (form-service 는 JSON 도 수용).
  local form_json; form_json=$(yq eval -o=json -I=0 "$f" 2>/dev/null \
    | jq -c 'walk(if type=="object" and has("signpostPosition") then del(.signpostPosition) else . end)')
  local form_str; form_str=$(jq -Rs '.' < "$f")
  local body; body=$(mktemp /tmp/form-imp.XXXXXX)
  if [[ -n "$form_json" ]]; then
    jq -n --arg src "$src" --argjson form "$form_json" \
      '{name:"default", type:"requestForm", sourceId:$src, sourceType:"com.vmw.blueprint", form:($form|tojson), formFormat:"JSON", status:"ON"}' > "$body"
  else
    # YAML→JSON 변환 실패 시 원본 그대로 전송(기존 동작 보존)
    jq -n --arg src "$src" --argjson form "$form_str" \
      '{name:"default", type:"requestForm", sourceId:$src, sourceType:"com.vmw.blueprint", form:$form, formFormat:"YAML", status:"ON"}' > "$body"
  fi

  local hdr; hdr=$(mktemp /tmp/form-imp-hdr.XXXXXX)
  local resp; resp=$(mktemp /tmp/form-imp-resp.XXXXXX)
  local code
  code=$(curl -sk -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d @"${body}" \
    -D "${hdr}" \
    -o "${resp}" -w "%{http_code}" \
    "https://${VCFA_FQDN}/form-service/api/forms")
  rm -f "${body}"

  if [[ "${code}" != "201" ]]; then
    echo "ERROR: form import HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${hdr}" "${resp}"; return 1
  fi

  # form id 는 Location 헤더에서 추출
  local loc form_id
  loc=$(awk -F': ' 'tolower($1)=="location"{gsub(/\r/,"",$2);print $2; exit}' "${hdr}")
  form_id="${loc##*/}"
  rm -f "${hdr}" "${resp}"

  export VCFA_FORM_ID="$form_id"
  echo "OK: form imported"
  echo "    file     = ${f}"
  echo "    source   = ${src}  (catalog item)"
  echo "    form-id  = ${form_id}    (셸에 VCFA_FORM_ID export)"
}

form_remote_export() {
  # Usage: form_remote_export <form-id> [out-file|sub-dir] [catalog-item-name]
  # form 본문(.form 필드)을 파일로 저장. formFormat 에 따라 .yml / .json.
  #   <form-id>          : 필수 — POST /forms 응답 Location 헤더의 마지막 segment
  #   2번째 인자 종류:
  #     - 디렉터리면 → 파일명은 custom_<catalog-name|form-id>.yml 자동
  #     - 그 외 → 지정 파일 경로
  #     - 생략 → forms/exported/custom_<catalog-name|form-id>.yml
  #   3번째 인자: 파일명에 쓸 사람-친화 이름 (생략 시 form-id)
  local id="${1:?Usage: form_remote_export <form-id> [out-file|sub-dir] [catalog-item-name]}"
  local hint="${2:-}"
  local pretty="${3:-${id}}"
  _remote_guard || return 1

  local resp; resp=$(mktemp /tmp/form-exp.XXXXXX)
  local code
  code=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "https://${VCFA_FQDN}/form-service/api/forms/${id}" \
    -o "${resp}" -w "%{http_code}")
  if [[ "$code" != "200" ]]; then
    echo "ERROR: form GET HTTP=${code}" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "${resp}"; return 1
  fi

  # 응답에 form 본문 + formFormat 들어있음
  local fmt; fmt=$(jq -r '.formFormat // "YAML"' "${resp}")
  local ext="yml"
  [[ "$fmt" == "JSON" ]] && ext="json"

  local out
  if [[ -z "$hint" ]]; then
    out="forms/exported/custom_${pretty}.${ext}"
  elif [[ "$hint" == */ ]] || [[ -d "$hint" ]] || [[ "$hint" =~ ^forms/[^/]+$ ]]; then
    local dir="${hint%/}"
    out="${dir}/custom_${pretty}.${ext}"
  else
    out="$hint"
  fi

  mkdir -p "$(dirname "$out")"
  jq -r '.form // ""' "${resp}" > "$out"
  echo "OK: exported — form-id=${id}  format=${fmt}  → ${out}"
  ls -la "$out"
  rm -f "${resp}"
}

# 대화식 — 카탈로그 item 선택 → 사용자가 form-id 입력 → 다운로드.
# Form 서버 list endpoint 가 없어 자동 매핑 불가. form_remote_import 직후 받은
# form-id 를 메모해두거나, VCFA_FORM_ID 가 셸에 살아있을 때 사용.
# Usage: form_select_export [sub-dir]
form_select_export() {
  _remote_guard || return 1
  local sub="${1:-forms/exported}"

  # 카탈로그 item 보여줌 — 사용자에게 어떤 form 이 어느 item 과 연결됐는지 힌트
  local resp; resp=$(mktemp /tmp/cat-sel.XXXXXX)
  vcfa_api_get "https://${VCFA_FQDN}/catalog/api/items?page=0&size=200" > "${resp}" \
    || { rm -f "${resp}"; return 1; }
  local n; n=$(jq '.content | length' "${resp}")

  echo "참고 — 현재 카탈로그 item (form 적용 대상이 될 수 있는 후보):"
  if [[ "$n" -eq 0 ]]; then
    echo "  (없음)"
  else
    jq -r '.content[] | "  \(.name)  item-id=\(.id)"' "${resp}"
  fi
  rm -f "${resp}"

  echo ""
  echo "ℹ️  Form 서버 list endpoint 가 없어 form-id 로 직접 export 합니다."
  echo "   form-id 는 form_remote_import 시 응답 Location 헤더의 마지막 segment."
  echo "   (셸에 VCFA_FORM_ID 가 살아있으면 기본값으로 사용)"
  echo ""
  printf "form-id [%s] (q=취소): " "${VCFA_FORM_ID:-입력 필요}"
  local fid; _vcfa_read_line fid
  fid="${fid:-${VCFA_FORM_ID:-}}"
  if [[ "$fid" == "q" || -z "$fid" ]]; then echo "취소"; return 1; fi

  printf "파일명에 쓸 이름 [%s]: " "form-${fid:0:8}"
  local pretty; _vcfa_read_line pretty
  pretty="${pretty:-form-${fid:0:8}}"

  form_remote_export "$fid" "${sub}/" "$pretty"
}

form_remote_delete() {
  local id="${1:?Usage: form_remote_delete <form-id>}"
  _remote_guard || return 1
  local code
  code=$(curl -sk -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o /dev/null -w "%{http_code}" \
    "https://${VCFA_FQDN}/form-service/api/forms/${id}")
  if [[ "${code}" == "204" || "${code}" == "200" ]]; then
    echo "OK: form deleted — id=${id}"
  else
    echo "ERROR: delete HTTP=${code}" >&2; return 1
  fi
}

# ============================================================
# All-in-one — blueprint import → release → form (한 줄로)
# ============================================================

# Usage: bp_set_form <blueprint-id> <form-file> [bp-name]
#   커스텀 폼을 *블루프린트에* set — VCF Automation 9.x 카탈로그가 실제로 쓰는 곳.
#   ★ 반드시 release 前에 호출해야 카탈로그 item 이 이 폼을 가져감.
#   (form-service 의 form_remote_import 는 9.x 카탈로그가 안 씀 — 그쪽은 무시됨.)
bp_set_form() {
  local bpid="${1:?Usage: bp_set_form <blueprint-id> <form-file> [bp-name]}"
  local f="${2:?form-file 필요}"
  local name="${3:-}"
  [[ -f "$f" ]] || { echo "ERROR: form file not found: $f" >&2; return 1; }
  _remote_guard || return 1
  require_cmd yq || return 1
  require_cmd jq || return 1
  if [[ -z "$name" ]]; then
    name=$(curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
      "https://${VCFA_FQDN}/blueprint/api/blueprints/${bpid}?apiVersion=2020-08-25" | jq -r '.name // empty')
  fi
  local formjson; formjson=$(yq eval -o=json -I=0 "$f") \
    || { echo "ERROR: form YAML→JSON 변환 실패: $f" >&2; return 1; }
  # ★ 방어: layout 의 signpostPosition 키는 이 빌드에서 드롭다운 렌더링을 깨뜨림(무한 로딩).
  #   stale 폼 파일에 남아 있어도 전송 직전 재귀 제거. (schema 의 signpost: 는 유지)
  formjson=$(printf '%s' "$formjson" | jq -c 'walk(if type=="object" and has("signpostPosition") then del(.signpostPosition) else . end)') \
    || { echo "ERROR: form signpostPosition strip 실패: $f" >&2; return 1; }
  local body; body=$(jq -n --arg name "$name" --arg id "$bpid" --arg form "$formjson" \
    '{name:$name, type:"requestForm", sourceId:$id, sourceType:"com.vmw.blueprint", status:"ON", styles:null, form:$form}')
  local resp; resp=$(mktemp /tmp/bp-setform.XXXXXX); local code
  code=$(curl -sk -o "$resp" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "$body" "https://${VCFA_FQDN}/blueprint/api/blueprints/${bpid}/form?apiVersion=2020-08-25")
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "ERROR: blueprint form set HTTP=$code" >&2
    jq . "$resp" 2>/dev/null >&2 || cat "$resp" >&2
    rm -f "$resp"; return 1
  fi
  rm -f "$resp"
  echo "OK: 블루프린트 폼 set — bp=${name} pages=$(yq eval '.layout.pages | length' "$f") (release 후 카탈로그 반영)"
}

content_publish() {
  # Usage: content_publish <blueprint.yaml> [form.yml] [bp-name]
  # blueprint 만 주면 release 까지. form 도 주면 form 적용까지.
  local bp="${1:?Usage: content_publish <blueprint.yaml> [form.yml] [bp-name]}"
  local form="${2:-}"
  local name="${3:-}"
  [[ -f "$bp" ]] || { echo "ERROR: blueprint file not found: $bp" >&2; return 1; }
  if [[ -n "$form" ]]; then
    [[ -f "$form" ]] || { echo "ERROR: form file not found: $form" >&2; return 1; }
  fi
  _remote_guard || return 1

  echo "[1/3] blueprint import"
  if [[ -n "$name" ]]; then
    bp_remote_import "$bp" "$name" || return 1
  else
    bp_remote_import "$bp" || return 1
  fi

  # ★ 폼은 release 前에 *블루프린트에* set 해야 카탈로그가 가져감 (9.x). form-service 아님.
  if [[ -n "$form" ]]; then
    echo ""
    echo "[2/3] 블루프린트에 커스텀 폼 set (release 前)"
    bp_set_form "$VCFA_BP_ID" "$form" "${name:-}" || return 1
  else
    echo ""
    echo "[2/3] form 생략"
  fi

  echo ""
  echo "[3/3] release + catalog 등록 (폼 포함)"
  bp_remote_release || return 1

  echo ""
  echo "=== 완료 ==="
  echo "  VCFA_BP_ID           = ${VCFA_BP_ID}"
  echo "  VCFA_CATALOG_ITEM_ID = ${VCFA_CATALOG_ITEM_ID:-?}"
  [[ -n "${VCFA_FORM_ID:-}" ]] && echo "  VCFA_FORM_ID         = ${VCFA_FORM_ID}"
  echo ""
  echo "  → 정리: bp_remote_delete (blueprint + catalog + form 자동)"
}

# ============================================================
# 일괄 import — blueprints/ 의 모든 운영 파일 + 짝 form 까지 한 번에
# ============================================================

content_publish_all() {
  # Usage: content_publish_all [--include-archive] [--cleanup-on-fail]
  # 기본: blueprints/ 의 archive/ 제외 모든 *.yaml/*.yml 을 import → 짝 form 을 블루프린트에 set(release 前) → release.
  #   ★ 폼은 bp_set_form 으로 *release 前에* 블루프린트에 set 해야 9.x 카탈로그가 가져감
  #     (form-service 의 form_remote_import 는 9.x 카탈로그가 안 씀). content_publish(단수)와 동일 경로.
  # 짝 form 은 content_pairs 와 동일한 키 매칭 규칙 사용.
  # --cleanup-on-fail: form set/release 실패 시 그 단계에서 만들어진 DRAFT blueprint 자동 삭제 (서버 잔여물 방지).
  local include_archive=0 cleanup_on_fail=0 skip_preflight=0
  for arg in "$@"; do
    case "$arg" in
      --include-archive)  include_archive=1 ;;
      --cleanup-on-fail)  cleanup_on_fail=1 ;;
      --skip-preflight)   skip_preflight=1 ;;
    esac
  done

  _remote_guard || return 1
  local root; root=$(_content_root)
  local bp_dir="${root}/blueprints" form_dir="${root}/forms"

  # release 전 preflight — $data vRO 액션이 vRO 에 존재 + output-type 이 Any 가 아닌지 검사.
  if [[ "$skip_preflight" -eq 0 ]] && typeset -f vco_check_data_actions >/dev/null 2>&1; then
    echo "=== preflight: \$data vRO 액션 점검 ==="
    if ! vco_check_data_actions "$bp_dir"; then
      echo "ERROR: preflight 실패 — 'vco_import_data_actions' 로 고친 뒤 재실행 (무시: --skip-preflight)." >&2
      return 1
    fi
    echo ""
  fi

  # archive 제외 (기본)
  local find_args=("-type" "f" "(" "-name" "*.yaml" "-o" "-name" "*.yml" ")")
  [[ "$include_archive" -eq 0 ]] && find_args+=("!" "-path" "*/archive/*")

  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$bp_dir" "${find_args[@]}" | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "blueprints/ 에 import 할 파일이 없음 (archive 제외)." >&2
    return 0
  fi

  echo "=== 일괄 import 대상 (${#files[@]} 개) ==="
  printf '  %s\n' "${files[@]}" | sed "s|${root}/||"
  echo ""

  local bp_file form_file key fkey results=() rc_global=0
  for bp_file in "${files[@]}"; do
    local rel="${bp_file#${root}/}"
    echo "==================================================================="
    echo "▶ ${rel}"
    echo "==================================================================="

    # 1) blueprint import (release 前 — 폼을 먼저 블루프린트에 set 해야 9.x 카탈로그가 가져감)
    bp_remote_import "$bp_file" || { results+=("FAIL  ${rel}  (import)"); rc_global=1; continue; }
    local imported_bp_id="${VCFA_BP_ID:-}"

    # 2) 짝 form 찾기 (파일명 키 매칭)
    key=$(basename "$bp_file" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
    form_file=""
    while IFS= read -r ff; do
      fkey=$(basename "$ff" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
      if [[ "$fkey" == "$key" ]]; then form_file="$ff"; break; fi
    done < <(find "$form_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/archive/*" | sort)

    # 3) 커스텀 폼을 *블루프린트에* set — ★ 반드시 release 前 (form-service 의 form_remote_import 는
    #    9.x 카탈로그가 안 쓰므로 사용하지 않음). bp_set_form 이 signpostPosition 도 제거.
    if [[ -n "$form_file" ]]; then
      echo ""
      echo "  ▷ 짝 form: ${form_file#${root}/}  (블루프린트에 set, release 前)"
      if ! bp_set_form "$imported_bp_id" "$form_file"; then
        results+=("FAIL  ${rel}  (form set)")
        rc_global=1
        if [[ "$cleanup_on_fail" -eq 1 && -n "$imported_bp_id" ]]; then
          echo "  cleanup: form set 실패 → DRAFT blueprint 삭제 ($imported_bp_id)"
          bp_remote_delete "$imported_bp_id" || true
        fi
        continue
      fi
    fi

    # 4) release (폼 포함 → 카탈로그 반영)
    if ! bp_remote_release; then
      results+=("FAIL  ${rel}  (release)")
      rc_global=1
      if [[ "$cleanup_on_fail" -eq 1 && -n "$imported_bp_id" ]]; then
        echo "  cleanup: 실패한 DRAFT blueprint 삭제 ($imported_bp_id)"
        bp_remote_delete "$imported_bp_id" || true
      fi
      continue
    fi

    if [[ -n "$form_file" ]]; then
      results+=("OK    ${rel}  + ${form_file#${root}/}  (form set→release)")
    else
      results+=("OK    ${rel}  (짝 form 없음 — skip)")
    fi
    echo ""
  done

  echo "==================================================================="
  echo "=== 결과 요약 ==="
  echo "==================================================================="
  printf '%s\n' "${results[@]}"
  echo ""
  echo "현재 서버 상태:"
  bp_remote_list
  echo ""
  catalog_remote_list

  return $rc_global
}

# ============================================================
# Drift 검사 — 로컬(레포) ↔ 라이브(VCFA) 비교 (import/덮어쓰기 前 안전장치)
# ------------------------------------------------------------
#   누가 VCFA UI 에서 blueprint/form 을 고쳤는지(=라이브가 레포와 달라졌는지) 검사.
#   blueprint .content 와 블루프린트에 붙은 form 을 *의미 비교*(공백·키순서 무시, signpostPosition 제거).
#   파일을 건드리지 않는 read-only. 반환값:
#     0 = drift 없음(라이브가 레포와 동일하거나, 라이브에 없어 신규 생성)
#     1 = drift 감지(라이브에 로컬과 다른 내용 — 덮어쓰면 손실)  ← 호출측이 확인 프롬프트 띄우면 됨
#   주의: 의미 비교라 드물게 오탐(서버 주입 필드 등) 가능 — '경고+확인'용 advisory 지표.
# ============================================================
_vcfa_norm_json() { # stdin: JSON → stdout: 키정렬 canonical (signpostPosition 제거)
  jq -S 'walk(if type=="object" and has("signpostPosition") then del(.signpostPosition) else . end)' 2>/dev/null
}
_vcfa_yaml_norm() { # $1: YAML 파일 → stdout: canonical JSON
  yq -o=json -I=0 '.' "$1" 2>/dev/null | _vcfa_norm_json
}

content_drift_check() {
  _remote_guard || return 2
  require_cmd jq || return 2
  require_cmd yq || return 2
  local root; root=$(_content_root)
  local bp_dir="${root}/blueprints" form_dir="${root}/forms"
  local pid; pid=$(_project_id) || return 2

  local list; list=$(mktemp /tmp/drift-list.XXXXXX)
  if ! vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" > "$list" 2>/dev/null; then
    echo "ERROR: 라이브 blueprint 목록 조회 실패 — drift 검사 불가" >&2; rm -f "$list"; return 2
  fi

  local files=()
  while IFS= read -r f; do files+=("$f"); done \
    < <(find "$bp_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/archive/*" | sort)
  if [[ ${#files[@]} -eq 0 ]]; then echo "  (검사할 로컬 blueprint 없음)"; rm -f "$list"; return 0; fi

  local drift=0 bp_file name id rel key fkey form_file
  for bp_file in "${files[@]}"; do
    rel="${bp_file#${root}/}"
    name=$(basename "$bp_file" | sed -E 's/\.(yaml|yml)$//; s/^blueprint_//')
    # 현재 project 동명 우선, 없으면 아무 project, 최신
    id=$(jq -r --arg n "$name" --arg pid "$pid" '
      [.content[]?|select(.name==$n)] as $b
      | (($b|map(select(.projectId==$pid)))|if length>0 then . else $b end)
      | sort_by(.updatedAt//.createdAt//"")|last|.id // empty' "$list")
    if [[ -z "$id" ]]; then
      echo "  ✚ ${name}: 라이브에 없음 → 신규 생성 (덮어쓰기 아님)"
      continue
    fi

    # 1) blueprint content
    local live_bp; live_bp=$(mktemp /tmp/drift-bp.XXXXXX)
    if vcfa_api_get "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}" > "$live_bp" 2>/dev/null; then
      local live_c local_c
      live_c=$(jq -r '.content // empty' "$live_bp" | yq -o=json -I=0 '.' 2>/dev/null | _vcfa_norm_json)
      local_c=$(_vcfa_yaml_norm "$bp_file")
      if [[ -z "$live_c" ]]; then
        echo "  ? ${name}: 라이브 content 비어/파싱불가 — 비교 생략"
      elif [[ "$live_c" != "$local_c" ]]; then
        echo "  ⚠ ${name}: blueprint 가 라이브에서 변경됨 — 덮어쓰면 라이브 수정분 손실 (${rel})"
        drift=1
      else
        echo "  ✓ ${name}: blueprint 동일"
      fi
    else
      echo "  ? ${name}: 라이브 blueprint(${id}) 조회 실패 — 비교 생략"
    fi
    rm -f "$live_bp"

    # 2) 짝 form (로컬에 있을 때만)
    key=$(basename "$bp_file" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
    form_file=""
    while IFS= read -r ff; do
      fkey=$(basename "$ff" | sed -E 's/\.(yaml|yml)$//; :a; s/^(blueprint_|custom_|vra_|vcfa_)//; ta')
      [[ "$fkey" == "$key" ]] && { form_file="$ff"; break; }
    done < <(find "$form_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/archive/*" | sort)
    if [[ -n "$form_file" ]]; then
      local live_form; live_form=$(vcfa_api_get \
        "https://${VCFA_FQDN}/blueprint/api/blueprints/${id}/form?apiVersion=2020-08-25" 2>/dev/null \
        | jq -r '.form // empty')
      if [[ -z "$live_form" ]]; then
        echo "      · form: 라이브에 폼 없음 → 새로 set (덮어쓰기 아님)"
      else
        local live_fn local_fn
        live_fn=$(printf '%s' "$live_form" | _vcfa_norm_json)
        local_fn=$(_vcfa_yaml_norm "$form_file")
        if [[ "$live_fn" != "$local_fn" ]]; then
          echo "      ⚠ form 이 라이브에서 변경됨 — 덮어쓰면 손실 (${form_file#${root}/})"
          drift=1
        else
          echo "      ✓ form 동일"
        fi
      fi
    fi
  done
  rm -f "$list"
  return $drift
}
