# ============================================================
# vRO 패키지 도우미 함수
# - vco_list_packages              : 현재 등록된 패키지 링크 목록
# - vco_package_details FILE       : 임포트 전 패키지 내용 미리보기 (실제 import 안 함)
# - vco_import_package FILE [OPTS] : 패키지 import (기본: overwrite=true)
# ============================================================

# 내부: vco api base URL
_vco_base() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  : "${TOKEN:?ERROR: TOKEN is not set}"
  echo "https://${VCFA_FQDN}/vco/api"
}

vco_export_package() {
  # Usage: vco_export_package PACKAGE_NAME [OUTPUT_FILE]
  # 기본 출력: packages/<PACKAGE_NAME>.package
  # 예: vco_export_package com.dk
  #     vco_export_package com.dk /tmp/com.dk-$(date +%F).package
  local pkg_name="${1:?Usage: vco_export_package PACKAGE_NAME [OUTPUT_FILE]}"
  local out="${2:-packages/${pkg_name}.package}"

  local base; base=$(_vco_base) || return 1
  mkdir -p "$(dirname "$out")"

  # 기본 옵션: 시크릿/속성값 빼고 export (원하면 ?param=true 로 query string 직접 붙여 호출).
  local query="exportConfigurationAttributeValues=false&exportConfigSecureStringAttributeValues=false&exportVersionHistory=false&exportGlobalTags=false&exportAsZip=false"

  local http_code
  http_code=$(
    curl -sk -L \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/zip,application/octet-stream,*/*" \
      "${base}/packages/${pkg_name}?${query}" \
      -o "${out}" \
      -w "%{http_code}"
  )

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo "ERROR: export failed for ${pkg_name}. HTTP=${http_code}" >&2
    if [[ -f "${out}" ]]; then
      # 에러 본문일 가능성 — 출력 후 삭제
      jq . "${out}" 2>/dev/null >&2 || cat "${out}" >&2
      rm -f "${out}"
    fi
    return 1
  fi

  local size; size=$(wc -c < "${out}")
  echo "OK: exported '${pkg_name}' → ${out} (${size} bytes, HTTP=${http_code})"
}

vco_package_details() {
  # import 시 어떤 element 가 추가/갱신/skip 될지 dry-run.
  # Usage: vco_package_details <package-file> [--raw]
  #   --raw : JSON 원본 그대로
  local pkg="${1:?Usage: vco_package_details <package-file> [--raw]}"
  local raw=0
  [[ "${2:-}" == "--raw" ]] && raw=1
  [[ -f "$pkg" ]] || { echo "ERROR: file not found: $pkg" >&2; return 1; }

  local base; base=$(_vco_base) || return 1
  local response_file http_code
  response_file="$(mktemp /tmp/vco-pkg-details.XXXXXX)"

  http_code=$(
    curl -sk -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/json" \
      -F "file=@${pkg}" \
      "${base}/packages/import-details" \
      -o "${response_file}" \
      -w "%{http_code}"
  )

  if [[ "${http_code}" != "200" ]]; then
    echo "ERROR: import-details failed. HTTP=${http_code}" >&2
    cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}" >&2
    rm -f "${response_file}"
    return 1
  fi

  if [[ $raw -eq 1 ]]; then
    jq . "${response_file}"
    rm -f "${response_file}"
    return 0
  fi

  # 1) 패키지 헤더
  jq -r '
    "[패키지]",
    "  name             : \(.packageName)",
    "  already-exists   : \(.packageAlreadyExists)",
    "  content-verified : \(.contentVerified)",
    "",
    "[인증서]",
    "  CN               : \(.certificateInfo.commonName)",
    "  organization     : \(.certificateInfo.organization)",
    "  valid            : \(.certificateInfo.validFromDate) ~ \(.certificateInfo.validUntilDate)",
    "  algorithm        : \(.certificateInfo.publicKeyAlgorithm)",
    "  valid / trusted  : \(.certificateValid) / \(.certificateTrusted)",
    ""
  ' "${response_file}"

  # 2) Element 표 — fileVer vs serverVer + 비교 + import 여부
  echo "[Element 목록 — import 했을 때 변화]"
  {
    printf 'NAME\tTYPE\tCATEGORY\tFILE_VER\tSERVER_VER\tCOMPARE\tIMPORT\tNAME_CONFLICT\tRENAMED\n'
    jq -r '
      .importElementDetails[]?
      | [
          .fileObjectName,
          .type,
          .fileCategory,
          .fileObjectVersion,
          (.serverObjectVersion // "-"),
          .versionComparison,
          (if .importIt then "yes" else "skip" end),
          (if .hasNameConflict then "yes" else "" end),
          (if .isRenamed then "yes" else "" end)
        ] | @tsv' "${response_file}"
  } | column -t -s $'\t'

  # 3) 요약 (count)
  echo ""
  jq -r '
    "[요약]",
    "  총 element        : \(.importElementDetails | length)",
    "  import 대상       : \([.importElementDetails[] | select(.importIt)] | length)",
    "  skip (동일 버전)  : \([.importElementDetails[] | select(.importIt | not) and (.versionComparison == "sameVersions")] | length)",
    "  버전 충돌         : \([.importElementDetails[] | select(.versionComparison != "sameVersions")] | length)",
    "  이름 충돌         : \([.importElementDetails[] | select(.hasNameConflict)] | length)"
  ' "${response_file}"

  rm -f "${response_file}"
}

vco_import_package() {
  local pkg="${1:?Usage: vco_import_package <package-file> [overwrite=true|false]}"
  local overwrite="${2:-true}"
  [[ -f "$pkg" ]] || { echo "ERROR: file not found: $pkg" >&2; return 1; }

  local base; base=$(_vco_base) || return 1
  local response_file http_code
  response_file="$(mktemp /tmp/vco-pkg-import.XXXXXX)"

  http_code=$(
    curl -sk -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/json" \
      -F "file=@${pkg}" \
      "${base}/packages?overwrite=${overwrite}&importConfigurationAttributeValues=false&tagImportMode=ImportButPreserveExistingValue&importConfigSecureStringAttributeValues=false" \
      -o "${response_file}" \
      -w "%{http_code}"
  )

  echo "HTTP_STATUS=${http_code}"
  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo "ERROR: import failed." >&2
    cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}" >&2
    rm -f "${response_file}"
    return 1
  fi

  jq . "${response_file}" 2>/dev/null || cat "${response_file}"
  rm -f "${response_file}"
}

# ============================================================
# vRO 액션 도우미 함수 (개별 .js 파일 단위 import)
# - vco_get_action_id MODULE NAME           : 있으면 UUID, 없으면 빈 문자열
# - vco_import_action FILE MODULE [OUT [IN]]: 신규 POST / 기존 PUT 자동
# - vco_import_all_js DIR MODULE            : 디렉터리의 모든 *.js 를 기본값(out=Any, inputs=[])으로 import
# ※ Python 액션의 runtime 필드는 미검증 — 일단 JS 만 안전.
# ※ output-type / input-parameters 가 명시 필요한 액션은 vco_import_action 으로 인자 명시.
# ============================================================

vco_list_actions() {
  # Usage: vco_list_actions [MODULE_PREFIX]
  # 인자 없으면 전체. 있으면 fqn prefix 매칭 (예: "com.vmk.dk" → com.vmk.dk/*)
  local prefix="${1:-}"
  local base; base=$(_vco_base) || return 1
  local resp; resp=$(mktemp /tmp/vco-actions.XXXXXX)
  # ★ 변수 대입(`$(...)`)은 일부 바이트(NUL 등)를 삼킴 → 응답에 제어문자가 있으면 jq 가 깨짐.
  #   파일로 받아 처리한다.
  curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "${base}/actions" -o "${resp}" || { rm -f "${resp}"; return 1; }

  if [[ -z "$prefix" ]]; then
    jq -r '
      ["NAME", "VERSION", "FQN"],
      (.link[]? | .attributes | from_entries | [.name, .version, .fqn])
      | @tsv' "${resp}" \
      | column -t -s $'\t'
  else
    jq -r --arg p "$prefix" '
      ["NAME", "VERSION", "FQN"],
      (.link[]? | .attributes | from_entries
        | select(.fqn | startswith($p + "/"))
        | [.name, .version, .fqn])
      | @tsv' "${resp}" \
      | column -t -s $'\t'
  fi
  rm -f "${resp}"
}

vco_get_action_id() {
  local module="${1:?module required}"
  local name="${2:?name required}"
  local base; base=$(_vco_base) || return 1
  curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "${base}/actions/${module}/${name}/" 2>/dev/null \
    | jq -r '.id // empty' 2>/dev/null
}

vco_import_action() {
  # Usage: vco_import_action FILE MODULE [OUTPUT_TYPE=Any] [INPUT_PARAMS_JSON=[]]
  # Example:
  #   vco_import_action actions/com.vmk.dk/getProjectsNames.js com.vmk.dk Array/string '[]'
  #   vco_import_action actions/com.vmk.dk/getNamespaces.js com.vmk.dk Array/string \
  #     '[{"name":"ProjectName","type":"string","description":""}]'
  local file="${1:?Usage: vco_import_action FILE MODULE [OUTPUT_TYPE] [INPUT_PARAMS_JSON]}"
  local module="${2:?module required (e.g., com.vmk.dk)}"
  local out_type="${3:-Any}"
  local inputs="${4:-[]}"

  [[ -f "$file" ]] || { echo "ERROR: file not found: $file" >&2; return 1; }
  local base; base=$(_vco_base) || return 1

  local fname; fname="$(basename "$file")"
  local name; name="${fname%.*}"            # 확장자 제거 (.js / .py)

  # JSON body 생성 (script 본문은 jq --arg 로 안전 인코딩)
  local body; body=$(mktemp /tmp/vco-action-body.XXXXXX)
  jq -n \
    --arg name    "$name" \
    --arg module  "$module" \
    --arg version "1.0.0" \
    --arg outType "$out_type" \
    --rawfile script "$file" \
    --argjson inputs "$inputs" \
    '{
       name: $name,
       module: $module,
       version: $version,
       "output-type": $outType,
       "input-parameters": $inputs,
       script: $script
     }' > "$body"

  # 신규 vs 업데이트 분기
  local existing_id method url
  existing_id=$(vco_get_action_id "$module" "$name")
  if [[ -n "$existing_id" ]]; then
    method="PUT"
    url="${base}/actions/${existing_id}"
  else
    method="POST"
    url="${base}/actions"
  fi

  local resp; resp=$(mktemp /tmp/vco-action-resp.XXXXXX)
  local http_code
  http_code=$(
    curl -sk -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "@${body}" \
      -o "${resp}" \
      -w "%{http_code}" \
      "$url"
  )

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "FAIL: $method ${module}/${name} HTTP=$http_code" >&2
    jq . "${resp}" 2>/dev/null >&2 || cat "${resp}" >&2
    rm -f "$body" "$resp"
    return 1
  fi

  echo "OK:   $method ${module}/${name} (HTTP=$http_code)"
  rm -f "$body" "$resp"
}

vco_import_all_js() {
  # Usage: vco_import_all_js DIR MODULE
  # 디렉터리의 *.js 전부를 기본값(output-type=Any, inputs=[])으로 import.
  # output-type/inputs 가 다른 액션이 있으면 그건 vco_import_action 으로 따로 호출.
  local dir="${1:?Usage: vco_import_all_js DIR MODULE}"
  local module="${2:?module required}"
  local f rc=0
  for f in "${dir}"/*.js; do
    [[ -e "$f" ]] || { echo "no .js in ${dir}" >&2; return 1; }
    vco_import_action "$f" "$module" || rc=1
  done
  return $rc
}

# vRO 패키지에 모듈의 모든 action 을 동기화 (누락된 element 추가).
# REST 만으로 패키지 멤버를 직접 추가하는 endpoint 는 없으나,
# "기존 서명된 .package 를 base 로 새 element 만 unsigned 로 추가한 ZIP" 을 import 하면
# vRO 가 받아들이는 우회법 (검증 완료 2026-05-24).
#
# Usage: vco_package_sync_module PACKAGE_NAME MODULE
# 예:    vco_package_sync_module com.dk com.vmk.dk
#
# 전제: vco_export_package PACKAGE_NAME 으로 base .package 가 packages/ 에 있어야 함
#       (없으면 자동 export 시도 후 진행)
vco_package_sync_module() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  : "${TOKEN:?ERROR: TOKEN is not set}"
  require_cmd jq      || return 1
  require_cmd unzip   || return 1
  require_cmd iconv   || return 1
  require_cmd python3 || return 1

  local pkg="${1:?Usage: vco_package_sync_module PACKAGE_NAME MODULE}"
  local mod="${2:?Usage: vco_package_sync_module PACKAGE_NAME MODULE}"
  local base; base=$(_vco_base) || return 1

  # 1) base .package 확보 — 없으면 export
  local base_pkg
  base_pkg=$(cd "${_VCFA_LIB_DIR}/.." && pwd)"/packages/${pkg}.package"
  if [[ ! -f "$base_pkg" ]]; then
    echo "  base .package 없음 → vRO 에서 export 받음"
    vco_export_package "$pkg" "$base_pkg" || return 1
  fi

  local work; work=$(mktemp -d /tmp/pkg-sync.XXXXXX)
  echo "작업 디렉터리: $work"
  (
    cd "$work"
    unzip -q "$base_pkg"
  ) || { rm -rf "$work"; echo "ERROR: base ZIP 풀기 실패" >&2; return 1; }

  # 2) 모듈의 모든 action id+name 수집
  local all_actions; all_actions=$(mktemp /tmp/sync-acts.XXXXXX)
  curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" \
    "${base}/actions" > "$all_actions"

  # 3) 누락된 action 만 추가
  local added=0 aid aname existing
  existing=$(ls "$work/elements" 2>/dev/null || true)

  while IFS=$'\t' read -r aid aname; do
    [[ -z "$aid" ]] && continue
    if echo "$existing" | grep -q "$aid"; then
      continue   # 이미 있음
    fi
    echo "  + ${mod}/${aname} (${aid})"
    mkdir -p "$work/elements/${aid}"
    # action ZIP 받아서 action-content → data
    curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/octet-stream" \
      "${base}/actions/${aid}" -o "$work/a.zip"
    unzip -p "$work/a.zip" action-content > "$work/elements/${aid}/data" || {
      echo "  ERROR: action-content 추출 실패 (${aid})" >&2; continue;
    }
    rm -f "$work/a.zip"
    # info
    cat > "$work/elements/${aid}/info" <<INFO_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
<properties>
<comment>UTF-16</comment>
<entry key="id">${aid}</entry>
<entry key="type">ScriptModule</entry>
</properties>
INFO_EOF
    # categories (UTF-16 인코딩)
    printf '<categories><category name='\''%s'\''><name><![CDATA[%s]]></name></category></categories>' \
      "$mod" "$mod" | iconv -t UTF-16 > "$work/elements/${aid}/categories"
    added=$((added+1))
  done < <(jq -r --arg p "${mod}/" '
    .link[]? | .attributes | from_entries
    | select(.fqn | startswith($p))
    | "\(.id)\t\(.name)"' "$all_actions")
  rm -f "$all_actions"

  echo ""
  echo "추가된 element: ${added}"
  if [[ "$added" -eq 0 ]]; then
    echo "OK: 누락된 element 없음 (패키지가 이미 모듈과 sync 됨)"
    rm -rf "$work"
    return 0
  fi

  # 4) ZIP 재생성 (python3 zipfile — system 에 zip 명령 없을 수 있음)
  local out="/tmp/${pkg}-sync.package"
  python3 - "$work" "$out" <<'PY'
import sys, os, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, root)
            zf.write(full, rel)
PY
  echo ""
  echo "=== 새 패키지 ZIP: ${out} ==="
  echo "  크기: $(wc -c < "$out") bytes  element 수: $(unzip -l "$out" | grep -c "elements/.*/data$")"

  # 5) import
  echo ""
  echo "=== import 시도 ==="
  vco_import_package "$out"
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    # base .package 갱신 (다음번 sync 의 base 로 사용)
    cp "$out" "$base_pkg"
    echo ""
    echo "  base .package 갱신: $base_pkg"
  fi

  rm -rf "$work" "$out"
  return $rc
}

vco_list_packages() {
  : "${VCFA_FQDN:?ERROR: VCFA_FQDN is not set}"
  : "${TOKEN:?ERROR: TOKEN is not set}"

  local vco_api_base="https://${VCFA_FQDN}/vco/api"
  local response_file
  local http_code

  response_file="$(mktemp /tmp/vco-packages.XXXXXX)"

  http_code=$(
    curl -sk \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/json" \
      "${vco_api_base}/packages" \
      -o "${response_file}" \
      -w "%{http_code}"
  )

  echo "HTTP_STATUS=${http_code}"

  if [[ "${http_code}" != "200" ]]; then
    echo "ERROR: failed to list packages." >&2
    cat "${response_file}" | jq . 2>/dev/null || cat "${response_file}"
    rm -f "${response_file}"
    return 1
  fi

  jq -r '
    ["REL", "TYPE", "HREF"],
    (.link[]? | [
      .rel,
      .type,
      .href
    ])
    | @tsv
  ' "${response_file}" | column -t -s $'\t'

  rm -f "${response_file}"
}
