# actions/

vRO Action 스크립트. 모듈 두 개:

- `com.vmk/` — REST 매니저 (다른 액션이 호출하는 헬퍼): `VraManager`, `VcsaManager`, `NsxtManager`, `ConfManager`, `TaskManager`
- `com.vmk.dk/` — 블루프린트 input의 `$data`에 값을 공급하는 데이터/헬퍼 액션

## 빠른 시작 — 패키지로 한 번에 (권장)

```text
vRO Client → Assets → Packages → Import
파일: ../packages/com.dk.package
→ 서명 검증 통과 → 두 모듈의 element들이 한 번에 들어옴
```

## 빠른 시작 — REST API (curl) 로 업로드

vRO에서 액션 단위 업로드는 권장되지 않습니다 — **패키지 단위가 표준**. curl 절차는 [../packages/README.md](../packages/README.md) 의 "REST API (curl) 로 자동 등록" 참조 (`POST /vco/api/packages` + VCFA 환경 검증 포인트).

새 액션을 추가했다면 vRO Client에서 패키지를 다시 export → [../packages/com.dk.package](../packages/com.dk.package) 덮어쓰기 → 위 curl 한 번으로 반영됩니다.

(꼭 액션 단위 API가 필요한 경우: vRO 표준 `POST /vco/api/actions` JSON body. 본 리포의 일반적 워크플로우는 아니므로 정식 절차를 두지 않음.)

## 빠른 시작 — 개별 등록 (패키지가 없을 때)

```text
1) vRO Client → Assets → Actions
2) 모듈 생성: "com.vmk" 와 "com.vmk.dk"
3) 각 .js 파일별로:
   - 액션 추가, 이름 = 파일명(확장자 제외)
   - 스크립트 본문 = 파일 내용 그대로
   - 입력/반환 타입 = 파일 상단 주석 참조 (예: // Inputs: 없음, // Return: Array/string)
4) 언어 선택:
   - 기본: JavaScript
   - Python(파일 안 `def handler`): `ChangePasswordHash` / `doubleBase64` / `validatePasswordMatch`
     → 런타임 **python:3.11** (9.1 에서 python:3.10 은 미지원). `ChangePasswordHash` 의 `import crypt` 는
       3.11 OK·**3.13 에서 제거**되므로 3.11~3.12 유지. (`vco_import_action` 이 `def handler` 감지해 자동 설정;
       바꾸려면 `VCO_PY_RUNTIME`.)
```

## 동작 확인

블루프린트의 input 드롭다운(Project / Namespace / VM Class / Image / Storage Class 등)이 채워지면 정상.

- vRO에 **`VCFA:Host` 등록 필요** — `getProjectsNames.js` 등이 `Server.findAllForType("VCFA:Host")` 로 찾음. 등록: `vcfa_register_host` 헬퍼. **카탈로그 폼까지 되려면 Shared Session + 지속 API 토큰(`VCFA_HOST_API_TOKEN`)** — [../docs/runbooks/deploy.md](../docs/runbooks/deploy.md) §빠른 실행.
- 액션 단위 검증: `vco_run_action com.vmk.dk/getProjectsNames` (값 나오면 정상). 카탈로그가 보는 값: `GET /catalog/api/items/<item>/versions/<v>/data/vro-actions/<m>/<n>?projectId=<pid>`.
- 자세한 매핑(어느 input ↔ 어느 액션)은 [../docs/runbooks/deploy.md](../docs/runbooks/deploy.md) §1-2.

### ★ 드롭다운 액션은 반드시 `{label,value}` (Array/Properties) — 2026-06-26 검증

dropDown input 에 값을 주는 `$data` 액션은 **`Array/Properties` 로 `{label,value}`** 를 반환해야 함:

```js
var p = new Properties(); p.put("label", name); p.put("value", name); results.push(p);
```

`Array/string` 으로 반환하면 카탈로그가 `{id,name}` 으로 래핑 → **UI 드롭다운이 value/label 을 못 찾아 무한로딩**(데이터는 HTTP 200 으로 옴!). release 는 통과하므로 "릴리스 OK인데 카탈로그만 무한로딩"으로 위장됨. getVMClass/getStorageClass 등은 이미 label/value, getProjectsNames/getNamespaces 도 2026-06-26 수정됨.

### `$data` 액션은 throw 금지

호스트/세션/조회 실패 시에도 **`return []`** (throw 하면 폼-서비스의 탭 데이터 평가가 깨져 전 드롭다운 무한로딩). getVMImage/getProjectsNames/getNamespaces 에 try/catch→`[]` 적용됨.

### 레거시 (com.vmk)

`VraManager`(vRA `vra-onprem` 호스트 + 구 `/iaas`·`/deployment` REST)는 **VCF 9.x All-Apps 비호환** — 등록 불가, 재작성 필요. `VcsaManager`/`NsxtManager` 는 `com.vmk.tool`·`com.vmk.driver` 모듈 의존(현재 부재). 폼 드롭다운과 무관(배포-시점 헬퍼).

## 주의

- 파일명·모듈 경로는 블루프린트의 `$data: /data/vro-actions/com.vmk.dk/<name>` URL과 1:1로 묶여 있음. **rename 시 블루프린트도 함께 갱신.**
- 알려진 오타(`getStroageClassManual*`)는 [../docs/tech-debt.md](../docs/tech-debt.md) 참조. (`getUbuntuVersion` 확장자 누락은 2026-06-25 해결)
