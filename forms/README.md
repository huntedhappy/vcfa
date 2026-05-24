# forms/

Service Broker Custom Form (YAML). 각 폼은 [../blueprints/](../blueprints/) 의 짝과 1:1. **반드시 짝 blueprint 를 먼저 Release 한 뒤** 적용.

## 운영용 파일

| 파일 | 짝이 되는 Blueprint |
|---|---|
| `vm/custom_vm.yml` | `blueprints/vm/blueprint_vm.yaml` |
| `vm/custom_vm_storageclass_manual.yml` | `blueprints/vm/blueprint_vm_storageclass_manual.yaml` |
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

## Import — REST 자동화 (권장, 검증 완료 2026-05-24)

전제: 짝 blueprint 가 이미 release 된 상태여야 함 (catalog item 이 있어야 sourceId 로 쓰임).

```bash
catalog_remote_list                                                 # ITEM_ID 확인
form_remote_import forms/vm/custom_vm.yml <ITEM_ID>                 # form 적용 (formFormat=YAML)
# 삭제:
form_remote_delete <form-id>
```

서버는 `form` 필드를 YAML 문자열로 받음 (`formFormat:"YAML"`). 사용자가 yq 로 미리 JSON 변환할 필요 없음.

## Import — UI (대안)

```text
1) Service Broker → Content & Policies → Content
2) 짝 카탈로그 항목 클릭 → "Customize Form"
3) 우상단 메뉴 → "Import" → 위 표의 짝 파일 선택
4) "Enable" → "Save"
```

폼이 blueprint 와 어긋나면(필드 누락·이름 불일치) **짝이 안 맞는 파일을 가져온 것**. 위 매칭표 또는 `content_pairs` 출력 재확인.
