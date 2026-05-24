# Runbook — 오프라인(에어갭) 환경에서 vRO 자산 준비

> **검증된 절차만 기록.** UI 외 REST 자동화 부분은 환경별 base URL/인증을 검증해서 채워야 합니다(아래 5절 참조).

---

## 1. 무엇을 오프라인으로 가져가야 하나

| 항목 | 출처 | 목적지 |
| --- | --- | --- |
| vRO 액션 스크립트 | [actions/](../../actions/) | vRO Client에서 직접 import |
| vRO 패키지 | [packages/com.dk.package](../../packages/com.dk.package) | vRO Client → Packages → Import |
| Cloud Assembly 블루프린트 | [blueprints/](../../blueprints/) | Cloud Assembly → Design → New from |
| Service Broker 폼 | [forms/](../../forms/) | Service Broker → Content & Policies → Custom Form |

본 리포에 들어 있는 모든 파일은 빌드 없이 그대로 임포트 가능합니다 — 인터넷 머신에서 추가로 받아야 할 산출물 없음.

---

## 2. vRO 패키지 무결성 확인

[packages/com.dk.package](../../packages/com.dk.package)는 서명된 zip. import 시 vRO가 `signatures/`와 인증서를 확인합니다. 사전 검증:

```bash
unzip -l packages/com.dk.package | grep -E "(signatures|certificates)/"
```

서명 인증서 정보가 포함되어 있어야 정상.

---

## 3. 이전 매체 권장

- USB·내부 아티팩트 저장소 사용 시 SHA256 등 체크섬 확인.
- 리포 자체를 클론으로 옮기는 것을 권장 — git 무결성으로 변조 감지.

```bash
git clone --depth 1 <internal-mirror-url>/vcfa.git
cd vcfa
git rev-parse HEAD       # 커밋 해시 기록 → 양 환경에서 일치 확인
```

---

## 4. 시크릿 처리

- 평문 비밀번호·토큰·API 키는 **이 리포에 절대 커밋하지 않음.**
- 운영 시크릿은 VCFA Secrets / vRO Configuration Element / 외부 KMS로 주입.
- 자세한 보호 장치는 [../security.md](../security.md) 참조.

---

## 5. REST 자동화로 업로드할 경우

각 자산 폴더의 README에 **VCFA에 업로드하는 curl 명령**이 정리되어 있습니다:

- [../../packages/README.md](../../packages/README.md) — vRO 패키지 (`POST /vco/api/packages`)
- [../../blueprints/README.md](../../blueprints/README.md) — Cloud Assembly 블루프린트
- [../../forms/README.md](../../forms/README.md) — Service Broker 커스텀 폼
- [../../actions/README.md](../../actions/README.md) — vRO 액션 (보통 패키지로 일괄 처리)

공통: VCFA 토큰 발급 절차는 [deploy.md §6](deploy.md) 참조.

---

## 6. 점검 체크리스트

- [ ] `git clone` 으로 자산 이전, 커밋 해시 일치 확인
- [ ] `unzip -l packages/com.dk.package`에 `signatures/` + `certificates/` 노출
- [ ] vRO 패키지 import 시 서명 경고 없음
- [ ] Cloud Assembly에서 블루프린트의 `$data` URL이 vRO 액션을 정상 해석 (드롭다운 채워짐)
- [ ] Service Broker 폼이 블루프린트 input과 1:1로 매칭됨
