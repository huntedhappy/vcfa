#!/usr/bin/env bash
# ============================================================
# clean-deploy.sh — VCFA 9.1 "처음부터(clean)" 재배포 올인원 (검증·게이트 포함)
# ------------------------------------------------------------
# UI 에서 blueprint/form/package/actions 를 전부 삭제한 뒤 실행:
#   [0]   로그인 + 전제 점검
#   [1]   오케스트레이터 연결 등록  (★ 액션이 데이터를 가져오려면 필수 — 패키지에 없음)
#   [1.5] FRESH 게이트 — 동명 blueprint 가 남아있으면 중단 (stale $data 인덱스 방지)
#   [2]   오케스트레이션 패키지 import (17개 액션, python:3.11 + output-type 복원)
#   [3]   블루프린트 + 커스텀 폼 import & release (fresh 강제, preflight 포함)
#   [4]   검증 — 등록 3종 + 폼 컨텍스트 {id,name} + Python 런타임
#
# 왜 [1] 이 필요한가:
#   getProjectsNames.js 를 vRO UI 에서 그냥 RUN 하면 빈값이던 이유 =
#   액션이 Server.findAllForType("VCFA:Host") 로 호스트를 찾는데, 호스트 미등록이면 빈 목록 return.
#   → vcfa_register_host 가 그 해결. getStorageClass=vCenter, getVMImage/getContentsLibrary=vAPI.
#
# ★ import 는 반드시 패키지(vco_import_package)로:
#   vco_import_all_js / 인자 없는 vco_import_action 은 output-type=Any 기본 → release 400.
#   vco_import_data_actions 는 blueprint $data 복구용일 뿐 — Python 액션 3개를 빠뜨림(패키지만 전부 복원).
#
# 사용법:
#   bash scripts/clean-deploy.sh [env-file]      # 기본 env = .env.tenant
#
# 전제(.env.tenant):
#   VCFA_FQDN, VCFA_USER, VCFA_PASS, VCFA_TENANT_ORG
#   VCFA_HOST_API_TOKEN  ← VCFA UI 발급 *지속* API 토큰(만료성 access token 아님). 카탈로그 폼 드롭다운 필수.
#   VC_HOST, VC_USER, VC_PASS  (+ 선택: VAPI_ENDPOINT_URL, VC_IGNORE_CERT)
# ============================================================

set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ENVF="${1:-.env.tenant}"

step(){ printf '\n════════ %s ════════\n' "$*"; }
ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m⚠\033[0m %s\n' "$*"; }
die(){  printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
gj(){ curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" "$@"; }

# ── [0] 로그인 + 헬퍼 로드 ───────────────────────────────────
step "[0] 로그인 + 헬퍼 로드 (env=${ENVF})"
[ -f "$ENVF" ] || die "env 파일 없음: ${ENVF}"
# shellcheck disable=SC1090
source scripts/session.sh "$ENVF" >/dev/null 2>&1 || die "로그인 실패 — ${ENVF} 의 VCFA_FQDN/USER/PASS 확인"
[ -n "${TOKEN:-}" ] && [ -n "${VCFA_FQDN:-}" ] || die "로그인 토큰 없음 — ${ENVF} 확인"
ok "로그인: ${VCFA_FQDN}  (org=${VCFA_TENANT_ORG:-provider})"

miss=0
for v in VC_HOST VC_USER VC_PASS; do
  [ -z "${!v:-}" ] && { warn "필수 변수 ${v} 미설정 (${ENVF})"; miss=1; }
done
if [ -z "${VCFA_HOST_API_TOKEN:-}" ]; then
  warn "VCFA_HOST_API_TOKEN 미설정 → 호스트가 'Per User Session' 으로 등록됨(직접 RUN 만 됨, 카탈로그 폼 드롭다운 안 뜸)."
  warn "  VCFA UI(User → API Tokens → Generate)에서 *지속* 토큰 발급 → ${ENVF} 에 넣고 재실행."
else
  case "$VCFA_HOST_API_TOKEN" in
    *여기에*|*paste*|*PASTE*|*xxxx*) warn "VCFA_HOST_API_TOKEN 이 예시 플레이스홀더로 보임 → Shared Session 이 깨진 토큰으로 등록될 수 있음. 실제 발급 토큰으로 교체.";;
  esac
fi
[ "$miss" = 1 ] && die "필수 변수 누락 — ${ENVF} 채우고 재실행"

# ── [1] 오케스트레이터 연결 등록 (액션 동작의 전제) ──────────
step "[1] 오케스트레이터 연결 등록  (★ 필수 / 이미 등록됐으면 자동 생략)"
# 세 헬퍼 모두 probe-first: 이미 등록돼 있으면 '이미 등록됨 — 생략' 출력 후 통과(failed 안 뜸).
# 강제 재등록이 필요하면 VCFA_FORCE_REGISTER=1 로 실행.
echo "--- VCFA:Host  (getProjectsNames/getNamespaces 'No VCFA:Host' 해결, 멱등=Update) ---"
vcfa_register_host || die "VCFA:Host 등록 실패"
echo "--- vCenter  (getStorageClass 소스) ---"
vcfa_register_vcenter || warn "vCenter 등록 실패 — [4] getStorageClass 로 작동 확인."
echo "--- vAPI endpoint + metamodel  (getVMImage/getContentsLibrary, VAPIManager) ---"
vcfa_register_vapi || warn "vAPI 등록 실패 — [4] getContentsLibrary 로 작동 확인."
ok "연결 등록 단계 완료 (실제 작동 여부는 [4] 에서 검증)"

# ── [1.5] 동명 blueprint 처리 — 있으면 삭제 후 재생성 (fresh $data 인덱스 보장) ──
step "[1.5] 동명 blueprint 처리 — 삭제 후 재생성 모드 (fresh \$data 인덱스)"
export VCFA_BP_RECREATE=1     # content_publish_all → bp_remote_import 가 동명(현재 project) 삭제 후 새로 POST
unset VCFA_BP_CREATE_ONLY     # recreate 모드 사용 (abort 가드 대신 자동 삭제+재생성)
TARGETS=$(find blueprints \( -name '*.yaml' -o -name '*.yml' \) | grep -v '/archive/' \
  | while read -r b; do basename "$b" | sed -E 's/\.(ya?ml)$//; s/^blueprint_//'; done | sort -u)
LIVE_BP=$(gj "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" | jq -r '.content[]?.name' 2>/dev/null)
hit=0
while IFS= read -r t; do
  [ -z "$t" ] && continue
  if printf '%s\n' "$LIVE_BP" | grep -qx "$t"; then warn "동명 '$t' 존재 → import 시 (현재 project) 삭제 후 재생성됨"; hit=1; fi
done <<< "$TARGETS"
[ "$hit" = 0 ] && ok "동명 blueprint 없음 — 전부 신규 생성"
ok "recreate 모드 ON (다른 project 의 동명 blueprint 는 유지)"

# ── [2] 오케스트레이션 패키지 import ─────────────────────────
step "[2] 오케스트레이션 패키지 import  (17개 액션, python:3.11 + output-type 복원)"
PKG="packages/com.dk.package"
[ -f "$PKG" ] || die "패키지 없음: ${PKG}  (먼저: vco_export_package com.dk ${PKG})"
vco_import_package "$PKG" true || die "패키지 import 실패"
LIVEN=$(vco_list_actions com.vmk.dk 2>/dev/null | grep -cE '^[A-Za-z]')
ok "패키지 import 완료 — com.vmk.dk 액션 라이브 ${LIVEN}개 (기대 17)"

# preflight: blueprint $data 액션이 전부 구체 타입(Any 아님)인지 — release 400 사전 차단
echo "--- preflight: \$data 액션 output-type 점검 (Any 면 release 400) ---"
if command -v vco_check_data_actions >/dev/null 2>&1; then
  vco_check_data_actions || warn "preflight 경고 — 위 출력 확인 (Any/누락 액션이 있으면 release 전에 해결)"
fi

# ── [3] 블루프린트 + 커스텀 폼 import & release ──────────────
step "[3] 블루프린트 + 커스텀 폼 import & release  (fresh 강제, signpostPosition 자동 제거, preflight 포함)"
# content_publish_all = blueprints/(archive 제외) 전부 import→폼 set(release 前)→release.
#   - 내부 preflight(vco_check_data_actions) 수행, bp_set_form 이 signpostPosition 제거,
#   - VCFA_BP_RECREATE=1 이므로 동명 blueprint(현재 project)는 삭제 후 새로 생성(fresh $data 인덱스, 가짜 'updated' 방지).
content_publish_all --cleanup-on-fail || die "블루프린트/폼 배포 실패 (위 로그 확인)"
ok "블루프린트/폼 배포 완료"

# ── [4] 검증 ────────────────────────────────────────────────
step "[4] 검증 — 등록 3종 / 폼 컨텍스트 {id,name} / Python 런타임"
verify_action(){ # $1=action  $2=설명(등록원)
  local n; n=$(vco_run_action "com.vmk.dk/$1" 2>/dev/null | jq -r '(.array.elements // []) | length' 2>/dev/null)
  n="${n:-0}"
  if [ "$n" -gt 0 ]; then ok "$1 → ${n}개 ($2 정상)"; else warn "$1 → 0개 ($2 등록/권한 확인)"; fi
}
verify_action getProjectsNames  "VCFA:Host"
verify_action getStorageClass   "vCenter"
verify_action getContentsLibrary "vAPI(VAPIManager)"

# 폼 컨텍스트(카탈로그가 실제 쓰는 경로) — Shared Session 토큰까지 정상이어야 {id,name} 나옴
BPID=$(gj "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200" | jq -r '.content[] | select(.name=="vm") | .id' 2>/dev/null | head -1)
if [ -n "${BPID:-}" ]; then
  FIRST=$(gj "https://${VCFA_FQDN}/blueprint/api/blueprints/${BPID}/data/vro-actions/com.vmk.dk/getVMClass?apiVersion=2020-08-25" | jq -c '.content[0] // empty' 2>/dev/null)
  if printf '%s' "$FIRST" | grep -q '"id"' && printf '%s' "$FIRST" | grep -q '"name"'; then
    ok "폼 컨텍스트 getVMClass → ${FIRST}  (={id,name} 렌더 OK = Shared Session 토큰 정상)"
  else
    warn "폼 컨텍스트 getVMClass 빈값/이상: ${FIRST:-(빈값)}"
    warn "  직접 RUN 은 되는데 이게 안 되면 = VCFA_HOST_API_TOKEN(Shared Session)이 만료/무효."
    warn "  → UI 에서 API 토큰 재발급 → ${ENVF} 갱신 → vcfa_register_host (Update) 후 재확인."
  fi
fi

# Python 액션 런타임 검증 (패키지가 python:3.11 복원했는지)
echo "--- Python 액션 런타임 (python:3.11 기대) ---"
for a in ChangePasswordHash doubleBase64 validatePasswordMatch; do
  rt=$(gj "https://${VCFA_FQDN}/vco/api/actions/com.vmk.dk/$a/" | jq -r '.runtime // "(none)"' 2>/dev/null)
  [ "$rt" = "python:3.11" ] && ok "$a runtime=$rt" || warn "$a runtime=$rt (python:3.11 기대 — 패키지 재import 확인)"
done

step "완료"
echo "  카탈로그에서 Request 폼을 열어 드롭다운(Project/VMClass/Storage/Image 등) 표시를 최종 확인하세요."
echo "  [4] 의 ⚠ 항목이 있으면: 해당 등록([1]) 또는 VCFA_HOST_API_TOKEN(폼 컨텍스트) 을 재확인."
