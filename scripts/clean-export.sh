#!/usr/bin/env bash
# ============================================================
# clean-export.sh — VCFA(live) → 레포로 받아오기 (live 가 정본)
# ------------------------------------------------------------
# VCFA 에서 테스트가 끝난 상태(=최신)를 정본으로 보고, 로컬 관리 파일을 지운 뒤
# 라이브에서 다시 받아 각 폴더에 저장한다:
#   packages   → packages/com.dk.package
#   actions    → actions/com.vmk.dk/<name>.js          (라이브 .script)
#   blueprints → blueprints/<dir>/blueprint_<name>.yaml (라이브 .content)
#   forms      → forms/<dir>/custom_<name>.yml          (★ 블루프린트에 붙은 폼에서, form-service 아님)
#
# clean-deploy.sh 의 역방향. 받은 뒤 git diff 로 확인하고 커밋하면 됨(= git 이 안전망).
#
# 사용법:
#   bash scripts/clean-export.sh [env-file]      # 기본 env = .env.tenant
#
# 전제: .env.tenant 의 로그인 값만 있으면 됨 — VCFA_FQDN / VCFA_USER / VCFA_PASS / VCFA_TENANT_ORG.
#   (VC_HOST/VCFA_HOST_API_TOKEN 등은 import(등록) 전용 — export 엔 불필요)
#
# 매핑(아래 MAP): live blueprint 이름 ↔ 레포 blueprint/form 경로.
#   MAP 에 없는 라이브 블루프린트는 blueprints/exported, forms/exported 로 받고 경고.
#   블루프린트를 추가하면 이 MAP 에 한 줄 추가.
# ============================================================

set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ENVF="${1:-.env.tenant}"

# name | blueprint-path | form-path
MAP="
vm|blueprints/vm/blueprint_vm.yaml|forms/vm/custom_vm.yml
vm_storageclass_manual|blueprints/vm/blueprint_vm_storageclass_manual.yaml|forms/vm/custom_vm_storageclass_manual.yml
vra_cluster|blueprints/cluster/blueprint_vra_cluster.yaml|forms/cluster/custom_cluster.yml
"
PKG_NAME="com.dk"
PKG_OUT="packages/com.dk.package"
ACT_MODULE="com.vmk.dk"          # 활성 모듈만 (com.vmk 레거시는 제외 — 별도 정리 대상)

step(){ printf '\n════════ %s ════════\n' "$*"; }
ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m⚠\033[0m %s\n' "$*"; }
die(){  printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
gj(){ curl -sk -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json" "$@"; }

# ── [0] 로그인 ───────────────────────────────────────────────
step "[0] 로그인 + 헬퍼 로드 (env=${ENVF})"
[ -f "$ENVF" ] || die "env 파일 없음: ${ENVF}"
# shellcheck disable=SC1090
source scripts/session.sh "$ENVF" >/dev/null 2>&1 || die "로그인 실패 — ${ENVF} 의 VCFA_FQDN/USER/PASS 확인"
[ -n "${TOKEN:-}" ] && [ -n "${VCFA_FQDN:-}" ] || die "로그인 토큰 없음 — ${ENVF} 확인"
ok "로그인: ${VCFA_FQDN}  (org=${VCFA_TENANT_ORG:-provider})"
command -v yq >/dev/null 2>&1 || die "yq 필요 (폼 JSON→YAML 변환)"

BPLIST=$(gj "https://${VCFA_FQDN}/blueprint/api/blueprints?page=0&size=200")
bp_id_by_name(){ printf '%s' "$BPLIST" | jq -r --arg n "$1" '[.content[]?|select(.name==$n)]|sort_by(.updatedAt//.createdAt//"")|last|.id // empty'; }

# ── [1] 패키지 ───────────────────────────────────────────────
step "[1] 패키지 export → ${PKG_OUT}"
rm -f "$PKG_OUT"
vco_export_package "$PKG_NAME" "$PKG_OUT" >/dev/null 2>&1 && ok "$PKG_OUT ($(wc -c <"$PKG_OUT" 2>/dev/null) bytes)" || die "패키지 export 실패 (${PKG_NAME})"

# ── [2] actions (활성 모듈) ──────────────────────────────────
step "[2] actions export → actions/${ACT_MODULE}/  (기존 .js 삭제 후 라이브 .script 로 재생성)"
mkdir -p "actions/${ACT_MODULE}"
rm -f "actions/${ACT_MODULE}"/*.js
names=$(vco_list_actions "$ACT_MODULE" 2>/dev/null | awk 'NR>1 && $1 ~ /^[A-Za-z]/ {print $1}')
acnt=0
for a in $names; do
  scr=$(gj "https://${VCFA_FQDN}/vco/api/actions/${ACT_MODULE}/${a}/" | jq -r '.script // empty')
  if [ -n "$scr" ]; then printf '%s\n' "$scr" > "actions/${ACT_MODULE}/${a}.js"; acnt=$((acnt+1)); fi
done
ok "actions ${acnt}개 받음 (com.vmk 레거시는 의도적으로 제외)"

# ── [3] blueprints + forms ───────────────────────────────────
step "[3] blueprints + forms export (★ 폼은 블루프린트에 붙은 것에서)"
# 관리 파일 일괄 삭제 (archive/ · README 는 보존) → stale 제거
find blueprints \( -name 'blueprint_*.yaml' -o -name 'blueprint_*.yml' \) -not -path '*/archive/*' -delete 2>/dev/null
find forms \( -name 'custom_*.yml' -o -name 'custom_*.yaml' \) -not -path '*/archive/*' -delete 2>/dev/null

export_form(){ # $1=bpId $2=formpath
  local fs; fs=$(gj "https://${VCFA_FQDN}/blueprint/api/blueprints/${1}/form?apiVersion=2020-08-25" | jq -r '.form // empty')
  if [ -z "$fs" ]; then return 2; fi          # 폼 없음
  mkdir -p "$(dirname "$2")"
  printf '%s' "$fs" | yq -p=json -o=yaml '.' > "$2" 2>/dev/null || return 1
  return 0
}

# 3-1. MAP 의 운영 블루프린트
mapped_names=""
while IFS='|' read -r nm bppath formpath; do
  [ -z "$nm" ] && continue
  mapped_names="${mapped_names} ${nm}"
  id=$(bp_id_by_name "$nm")
  if [ -z "$id" ]; then warn "라이브에 blueprint '${nm}' 없음 — 건너뜀 (레포 파일은 삭제된 상태로 유지)"; continue; fi
  bp_remote_export "$id" "$bppath" >/dev/null 2>&1 && ok "blueprint ${nm} → ${bppath}" || warn "blueprint ${nm} export 실패"
  case "$(export_form "$id" "$formpath"; echo $?)" in
    0) ok "form ${nm} → ${formpath}";;
    2) warn "blueprint '${nm}' 에 붙은 폼 없음 — ${formpath} 생성 안 함";;
    *) warn "form ${nm} export 실패";;
  esac
done <<< "$(printf '%s\n' "$MAP" | sed '/^[[:space:]]*$/d')"

# 3-2. MAP 에 없는 라이브 블루프린트 → exported/ 로
while IFS= read -r nm; do
  [ -z "$nm" ] && continue
  printf '%s\n' $mapped_names | grep -qx "$nm" && continue
  id=$(bp_id_by_name "$nm")
  [ -z "$id" ] && continue
  warn "MAP 에 없는 라이브 blueprint '${nm}' → blueprints/exported, forms/exported 로 받음 (필요하면 MAP 에 추가)"
  bp_remote_export "$id" "blueprints/exported/blueprint_${nm}.yaml" >/dev/null 2>&1 && ok "  blueprint ${nm} → blueprints/exported/"
  export_form "$id" "forms/exported/custom_${nm}.yml" >/dev/null 2>&1 && ok "  form ${nm} → forms/exported/"
done <<< "$(printf '%s' "$BPLIST" | jq -r '.content[]?.name' | sort -u)"

# ── [4] 변경 요약 ────────────────────────────────────────────
step "[4] 변경 요약 — git 으로 확인 후 커밋하세요"
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  git status --short -- packages actions blueprints forms 2>/dev/null | sed 's/^/  /' | head -60
  echo
  echo "  검토:  git diff -- blueprints forms actions"
  echo "  복구(잘못받음):  git checkout -- packages actions blueprints forms"
  echo "  반영:  git add -A && git commit && git push origin main"
else
  echo "  (git 저장소 아님 — 변경 수동 확인)"
fi
step "완료"
