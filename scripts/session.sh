#!/usr/bin/env bash
# Usage:
#   source scripts/session.sh        # ← 이렇게 호출 (.env / 함수 / TOKEN 이 현재 셸에 남음)
#
# Note:
#   ./scripts/session.sh 처럼 실행하면 자식 프로세스라 효과가 부모 셸에 안 남습니다.

# 잘못된 사용 방어 — execute 시 안내 후 종료
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: this script must be sourced, not executed." >&2
  echo "       run:  source scripts/session.sh" >&2
  exit 2
fi

# bash 에서는 ${BASH_SOURCE[0]} 가 sourced 파일 경로, zsh 에서는 그게 비어 있고 ${0} 가 sourced 파일 경로.
_VCFA_SELF="${BASH_SOURCE[0]:-$0}"
_VCFA_SCRIPT_DIR="$(cd "$(dirname "${_VCFA_SELF}")" && pwd)"
_VCFA_ROOT_DIR="$(cd "${_VCFA_SCRIPT_DIR}/.." && pwd)"

# 1) env 로드 — 인자로 파일 지정 가능 (기본: .env)
#    예) source scripts/session.sh .env.tenant
#        source scripts/session.sh /path/to/.env.prod
_VCFA_ENV_ARG="${1:-.env}"
if [[ "${_VCFA_ENV_ARG}" = /* ]]; then
  _VCFA_ENV_FILE="${_VCFA_ENV_ARG}"
else
  _VCFA_ENV_FILE="${_VCFA_ROOT_DIR}/${_VCFA_ENV_ARG}"
fi
if [[ -f "${_VCFA_ENV_FILE}" ]]; then
  echo "loading env: ${_VCFA_ENV_FILE}"
  # env 파일이 바뀌면 이전 세션의 TOKEN 과 선택 상태를 폐기 (다른 user/org 일 수 있음).
  # mode trigger (VCFA_TENANT_ORG) 와 selection state 둘 다 새 env 가 덮어쓰도록.
  unset TOKEN
  unset VCFA_TENANT_ORG
  unset VCFA_ORG_NAME VCFA_ORG_ID _VCFA_ORG_CACHED_NAME
  unset VCFA_PROJECT_NAME VCFA_PROJECT_ID
  unset VCFA_NS_NAME VCFA_NS_ID
  source "${_VCFA_ENV_FILE}"
  # _env_set 이 같은 파일에 persist 하도록 경로 export
  export VCFA_ENV_FILE="${_VCFA_ENV_FILE}"
else
  echo "ERROR: env file not found: ${_VCFA_ENV_FILE}" >&2
  unset _VCFA_SELF _VCFA_SCRIPT_DIR _VCFA_ROOT_DIR _VCFA_ENV_ARG _VCFA_ENV_FILE
  return 1
fi
unset _VCFA_ENV_ARG _VCFA_ENV_FILE

# 2) lib 로드
source "${_VCFA_SCRIPT_DIR}/vcfa-api-lib.sh"
source "${_VCFA_SCRIPT_DIR}/vcfa-vro-package-lib.sh"
source "${_VCFA_SCRIPT_DIR}/vcfa-content-lib.sh"

# 3) 기존 TOKEN 검증 — sessions/current 호출해서 200 아니면 무효 → unset 후 재로그인
if [[ -n "${TOKEN:-}" ]]; then
  _vcfa_code=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json;version=${VCFA_API_VERSION:-9.1.0}" \
    "https://${VCFA_FQDN}/cloudapi/1.0.0/sessions/current")
  if [[ "${_vcfa_code}" != "200" ]]; then
    echo "기존 TOKEN 무효 (HTTP=${_vcfa_code}) → 재로그인" >&2
    unset TOKEN
  fi
  unset _vcfa_code
fi

# 4) TOKEN 없으면 로그인 (위에서 unset 됐거나 처음부터 없거나)
if [[ -z "${TOKEN:-}" ]]; then
  login_vcfa || { unset _VCFA_SELF _VCFA_SCRIPT_DIR _VCFA_ROOT_DIR; return 1; }
fi

echo "OK: VCFA 세션 활성 (TOKEN length=${#TOKEN})"

unset _VCFA_SELF _VCFA_SCRIPT_DIR _VCFA_ROOT_DIR
