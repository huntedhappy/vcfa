# Security Notes

> 현재 리포에서 **직접 확인된** 보안 관련 사항만 기록합니다.
> 추측·일반론·미확인 위협 모델은 넣지 않습니다.

## 확인된 보호 장치

### 비밀번호 입력
[blueprints/vm/blueprint_vm.yaml](../blueprints/vm/blueprint_vm.yaml)의 `adminPassword` input은 다음 속성으로 보호됩니다.
```yaml
adminPassword:
  type: string
  encrypted: true
  writeOnly: true
```
- `encrypted: true` → Cloud Assembly 측에서 저장 시 암호화.
- `writeOnly: true` → 폼/배포 결과에 평문 노출 금지.

### 비밀번호 해싱
[actions/com.vmk.dk/ChangePasswordHash.js](../actions/com.vmk.dk/ChangePasswordHash.js) (실체는 Python action):
- `crypt.crypt(plain_pw, crypt.mksalt(crypt.METHOD_SHA512))`를 사용해 `$6$` SHA-512 해시 생성.
- 로그에는 평문/해시를 남기지 않고 **입력 길이**와 **소요 시간**만 출력.

### 리포지토리 비밀 제외
`.gitignore`:
```
.ssh/
```
- SSH 키 디렉터리는 커밋 대상에서 제외.

### vRO 패키지 무결성
- [packages/com.dk.package](../packages/com.dk.package) 내부에 `signatures/` 및 인증서(`O=VMware,OU=Unknown,CN=Orchestrator ...`)가 포함되어 있어 vRO 가져오기 시 서명 검증이 가능합니다.

## 작업 시 주의 (검증된 원칙)

1. **시크릿/토큰/평문 비밀번호를 커밋하지 말 것.**
   - 새 input을 추가할 때 비밀이면 항상 `encrypted: true` + `writeOnly: true`.
2. **vRO 액션 로그에 비밀을 남기지 말 것.**
   - `ChangePasswordHash.js`와 같은 패턴(길이/시간만)을 유지.
3. **매니저 호스트 이름 하드코딩 주의.**
   - 예: [actions/com.vmk/VraManager.js](../actions/com.vmk/VraManager.js)는 `manager` 변수가 비어 있으면 `"VMK"`로 폴백. 실제 호스트명이 다른 환경에서는 명시적으로 전달해야 함.

## 아직 확인하지 못한 것

- vRO 측 인증서/서명 검증 정책(가져오는 환경 설정에 의존).
- REST 매니저들이 사용하는 자격 증명의 보관 위치(vRO Configuration Element로 추정되나 본 리포에 정의 파일 없음 → 미확인).
