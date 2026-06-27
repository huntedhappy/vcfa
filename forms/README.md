# forms/

Service Broker Custom Form (YAML). 각 폼은 [../blueprints/](../blueprints/) 의 짝과 1:1. **반드시 짝 blueprint 를 먼저 Release 한 뒤** 적용.

## 운영용 파일

| 파일 | 짝이 되는 Blueprint |
|---|---|
| `vm/custom_vm.yml` | `blueprints/vm/blueprint_vm.yaml` |
| `cluster/custom_cluster.yml` | `blueprints/cluster/blueprint_vra_cluster.yaml` |

`archive/` 는 이전·중복 폼 — **사용 금지**. 그중 `custom_vra_cluster.yml` 은 `cluster/custom_cluster.yml` 과 바이트 단위 동일.

## Import 전 로컬 검증

```bash
source scripts/session.sh

form_list                         # 페이지/필드 개수 한 줄 요약
form_check                        # 전체 YAML 문법 + 필수 키 (.layout.pages) 검증
form_check forms/vm/custom_vm.yml # 특정 파일만
form_show forms/vm/custom_vm.yml  # pages → sections → fields 트리
content_pairs                     # blueprint ↔ form 매칭 자동 추측 표
```

## Import — REST 자동화 (권장)

### ★ VCF Automation 9.x 에서 폼은 *블루프린트에* set 한다 (2026-06-26 검증)

카탈로그 요청 폼은 **블루프린트에 붙은 폼**(`POST /blueprint/api/blueprints/{bpId}/form`)을 씁니다. 그리고 **그 폼은 release 前에 set 해야** 카탈로그 item 이 가져갑니다. 그래서 순서는 **import → 폼 set → release**.

```bash
source scripts/session.sh .env.tenant
content_publish blueprints/vm/blueprint_vm.yaml forms/vm/custom_vm.yml   # import → bp_set_form → release (한 방)
# 또는 단계별:
#   bp_remote_import blueprints/vm/blueprint_vm.yaml
#   bp_set_form "$VCFA_BP_ID" forms/vm/custom_vm.yml      # ← release 前!
#   bp_remote_release
```

검증(카탈로그가 실제 서빙하는 폼):
```bash
# /catalog/api/items/<ITEM_ID>/versions/<V>/form 의 .form 안 layout.pages 가 커스텀 폼이면 OK
```

> **`form_remote_import`(form-service, `/form-service/api/forms`) 는 9.x 카탈로그가 쓰지 않습니다** — 거기 넣어도 카탈로그엔 안 보입니다(vRA 8.x Service Broker 잔재). `bp_set_form`/`content_publish` 를 쓰세요.
> 폼을 수정했으면 **반드시 다시 `content_publish`**(폼 set → 재release) 해야 반영됩니다. release 後에 폼만 바꾸면 카탈로그는 옛 release 의 폼을 계속 서빙합니다.

> 참고: 폼 내용이 이미 맞다면(=리포와 동일) 재생성해도 `form` 길이는 같습니다. **카탈로그 드롭다운이 무한로딩이면 폼/import 문제가 아니라** vRO 데이터소스 평가(호스트 세션·VCFA↔vRO 통합) 문제이니 [../docs/runbooks/deploy.md](../docs/runbooks/deploy.md) 트러블슈팅 표 참조.

## Import — UI (대안)

```text
1) Service Broker → Content & Policies → Content
2) 짝 카탈로그 항목 클릭 → "Customize Form"
3) 우상단 메뉴 → "Import" → 위 표의 짝 파일 선택
4) "Enable" → "Save"
```

폼이 blueprint 와 어긋나면(필드 누락·이름 불일치) **짝이 안 맞는 파일을 가져온 것**. 위 매칭표 또는 `content_pairs` 출력 재확인.

> **참고**: `blueprints/vm/blueprint_vm_windows.yaml` 은 **DRAFT (대응 폼 없음)** 입니다. cloudbase-init 기반 Windows VM 용으로, 네이티브 Windows VM 1개 생성해 YAML 정렬 후 폼 추가 예정.
