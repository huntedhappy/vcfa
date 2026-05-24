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
   - 예외: ChangePasswordHash.js → Python
   - 예외: getUbuntuVersion (확장자 없음) → 파일 내용 확인 후 언어 결정
```

## 동작 확인

블루프린트의 input 드롭다운(Project / Namespace / VM Class / Image / Storage Class 등)이 채워지면 정상.

- vRO에 `VCFA:Host` 가 등록되어 있어야 함 — `com.vmk.dk/getProjectsNames.js` 가 `Server.findAllForType("VCFA:Host", null)` 로 찾습니다.
- VRA 호스트 별칭 기본값은 `"VMK"` — `com.vmk/VraManager.js` 의 `_client` 폴백. 다른 이름이면 호출 시 `manager` 변수에 명시.

자세한 매핑(어느 input ↔ 어느 액션)은 [../docs/runbooks/deploy.md](../docs/runbooks/deploy.md) §1-2.

## 주의

- 파일명·모듈 경로는 블루프린트의 `$data: /data/vro-actions/com.vmk.dk/<name>` URL과 1:1로 묶여 있음. **rename 시 블루프린트도 함께 갱신.**
- 알려진 오타(`getStroageClassManual*`) 및 확장자 누락(`getUbuntuVersion`)은 [../docs/tech-debt.md](../docs/tech-debt.md) 참조.
