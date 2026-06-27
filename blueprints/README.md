# blueprints/

Cloud Assembly Cloud Template (YAML).

## 운영용 파일

| 파일 | 용도 | 짝이 되는 Form |
|---|---|---|
| `vm/blueprint_vm.yaml` | VM (표준) | `forms/vm/custom_vm.yml` |
| `cluster/blueprint_vra_cluster.yaml` | K8s 게스트 클러스터 | `forms/cluster/custom_cluster.yml` |

`archive/` 는 이전 버전 백업 — **운영 사용 금지**.

## Import 전 로컬 검증

```bash
source scripts/session.sh

bp_list                          # 운영 + archive 의 파일 한 줄 요약 (formatVersion, inputs/resources 개수)
bp_check                         # 전체 YAML 문법 + 필수 키 (formatVersion=1, .resources) 검증
bp_check blueprints/vm/blueprint_vm.yaml   # 특정 파일만
bp_show blueprints/vm/blueprint_vm.yaml    # inputs/resources 상세 (vRO action $data 바인딩 확인)
content_pairs                    # blueprint ↔ form 매칭 자동 추측 표
```

## Import — REST 자동화 (권장, 검증 완료 2026-05-24)

전제: `source scripts/session.sh .env.tenant` 후 `vcfa_select_project` 한 번.

```bash
bp_remote_import blueprints/vm/blueprint_vm.yaml          # DRAFT 생성, id 반환
bp_remote_release <bp-id>                                 # release → catalog 자동 등록
# 짝 form 적용:
catalog_remote_list                                       # ITEM_ID 확인
form_remote_import forms/vm/custom_vm.yml <ITEM_ID>
```

자세한 동작 — [../README.md](../README.md) 의 "Blueprint REST 자동화" 절.

## Import — UI (대안)

```text
1) Cloud Assembly → Design → Cloud Templates → New
2) YAML 탭에 위 표의 파일 중 하나의 내용을 붙여넣기
3) "Test" 클릭 → input 드롭다운이 채워지면 vRO 액션 연결 OK
4) "Version" → "Release" 로 Service Broker에 게시
```

드롭다운이 비어 있으면 → [../actions/README.md](../actions/README.md) (액션이 vRO에 없거나 모듈명이 다름).

Import 직후 [../forms/README.md](../forms/README.md) 의 짝 form 을 같은 카탈로그 항목에 적용.
