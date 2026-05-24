# packages/

서명된 vRO 패키지 (`.package`). 내부에 [../actions/](../actions/) 의 element 들과 인증서가 묶여 있습니다.

## 현재 파일

| 파일 | 내용 |
|---|---|
| `com.dk.package` | `com.vmk.dk` + `com.vmk` 액션 묶음 (서명 포함) |

## Import 전 로컬 파일 검증 (offline — 서버 호출 없음)

```bash
source scripts/session.sh

pkg_list                              # packages/*.package 한 줄 요약 (element 수, 서명 여부, size)
pkg_check                             # 전체 ZIP 무결성 + dunes-meta-inf / signatures/ / certificates/ 검증
pkg_check packages/com.dk.package     # 특정 파일만
pkg_show  packages/com.dk.package     # 메타(이름/서명자/버전) + element 목록 (action 이름/타입/모듈)
```

## REST API 로 관리 (cloudapi 와 별도, vRO API 직접 호출)

> vRO API (`/vco/api/*`) 는 cloudapi 의 Bearer 토큰을 그대로 받아들이므로 **자동화 정상 작동**.
> (참고: Cloud Assembly 의 blueprint/form API 는 project-scoped RBAC 으로 막혀 자동화 불가 — 각 폴더 README 참조.)

```bash
# 1) 현재 vRO 의 패키지 링크 목록
vco_list_packages

# 2) Import 전 vRO 서버측 시각으로 미리보기 (file 도 함께 검증되지만 서버 호출)
vco_package_details packages/com.dk.package

# 3) Import (기본: overwrite=true, tagImportMode=ImportButPreserveExistingValue)
vco_import_package packages/com.dk.package
vco_import_package packages/com.dk.package false   # overwrite 끄고 싶을 때

# 4) Export — 현재 vRO 의 패키지를 .package 파일로 내려받기
vco_export_package com.dk                          # → packages/com.dk.package
vco_export_package com.dk /tmp/com.dk-$(date +%F).package
```

## Import 직후 검증

```bash
vco_list_actions com.vmk.dk          # 액션 목록에 새 element 표시되는지
vco_list_actions com.vmk             # (보조 패키지)
```

## UI 로 import (대안)

```text
vRO Client → Assets → Packages → Import → com.dk.package
→ 서명 검증 통과 → element 임포트 완료
```

## 패키지 구조 (검증용)

```bash
unzip -l packages/com.dk.package
```

`dunes-meta-inf`, `elements/<uuid>/{data,categories,info}`, `signatures/`, `certificates/` 구조. 서명 정보가 포함되어 있어 vRO import 시 무결성 검사를 수행.

## 새 액션 추가했을 때 흐름

1. `actions/com.vmk.dk/` 에 `.js` 파일 추가/수정
2. 개별 액션만 빠르게 반영: `vco_import_action actions/com.vmk.dk/new.js com.vmk.dk` (lib 함수, 자세한 옵션은 [../actions/README.md](../actions/README.md))
3. 검증 후 vRO Client 에서 패키지 export → 이 폴더에 덮어쓰기 (서명은 환경 인증서로 자동)
4. `git diff packages/` 로 변경 확인 후 커밋

## 주의

- 시크릿(비밀번호·토큰)은 `.env` 로만, **절대 커밋 금지**.
- `.package` 파일은 서명 포함 — 환경의 인증서로 export 해야 다른 vRO 에서 import 가능.
