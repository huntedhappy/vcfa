# Known Tech Debt

> 현재 리포에서 **직접 확인된** 정리 대상만 기록합니다.
> 우선순위/일정은 단정하지 않습니다 — 사실만.

## Duplicate files

### [forms/cluster/custom_cluster.yml](../forms/cluster/custom_cluster.yml) ≡ [forms/archive/custom_vra_cluster.yml](../forms/archive/custom_vra_cluster.yml)
- 두 파일은 바이트 단위로 동일 (`diff -q` 출력 없음, 둘 다 470줄).
- 2026-05-24 리오그 시 `custom_vra_cluster.yml`을 `forms/archive/`로 이동(중복으로 분류).
- 권장: 사용처 확인 후 archive 쪽 삭제. **본 시점 삭제하지 않음** — 외부 참조 가능성 미확인.

## Backup-named files

다음 파일은 이름 자체에 "이전 버전" 의도가 명시되어 있으나, 보존 시점/이유는 본 리포 내 명시가 없음.
- [blueprints/archive/blueprint_vm_original.yaml](../blueprints/archive/blueprint_vm_original.yaml)
- [forms/archive/custom_vm_original.yml](../forms/archive/custom_vm_original.yml)

권장: 유지/삭제 정책을 결정해 `docs/decisions/`에 기록.

## Naming inconsistencies

[actions/com.vmk.dk/](../actions/com.vmk.dk/) 내 파일명에 오타가 굳어 있음. 블루프린트 input의 `$data` 경로와 일치하므로 단순 rename은 호환성 위험.
- `getStroageClassManual.js` (Stroage ← Storage 오타)
- `getStroageClassManualOptionals.js` (동일)
- `getUbuntuVersion` — **확장자 누락** (`.js` 없음). 다른 액션은 모두 `.js`.
- 블루프린트 표기 혼용: `getNamespaces`(blueprint) vs 파일명 `getNameSpaces.js` — 호출 경로 케이스 민감 여부는 vRO 측 확인 필요(미확인).

권장: 변경 시 vRO 내 액션 ID와 블루프린트 `$data` URL을 함께 갱신.

## 그 외

- [actions/com.vmk/](../actions/com.vmk/)의 매니저별 `*.png` 스크린샷이 함께 커밋되어 있음 (총 ~1.4MB). 문서/참고 용도로 보이나 사용처 명시 없음.
