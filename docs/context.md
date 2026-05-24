# Project Context

> 이 문서는 **현재 리포지토리에서 직접 확인된 사실**만 기록합니다.
> 추측·미확인 내용은 넣지 않습니다. 갱신 시에도 같은 원칙을 지켜주세요.

## 범위

이 리포지토리는 **VCFA(VMware Cloud Foundation Automation)** 환경에서 사용하는
- VRA Cloud Assembly 블루프린트 (`blueprints/**/*.yaml`)
- VRA Service Broker 커스텀 폼 (`forms/**/*.yml`)
- vRO(Aria Orchestrator) 액션/매니저 스크립트 (`actions/`)
- vRO 패키지 (`packages/`)

만 포함합니다. 이 외 영역은 본 리포 범위가 아닙니다. 각 자산을 VCFA에 업로드하는 방법(UI 및 REST/curl)은 폴더별 README에 정리.

## 확인된 구성

### Blueprint (YAML)
| 파일 | 라인 수 | 비고 |
| --- | --- | --- |
| [blueprints/vm/blueprint_vm.yaml](../blueprints/vm/blueprint_vm.yaml) | 1428 | 현재 사용 중인 VM 배포 |
| [blueprints/vm/blueprint_vm_storageclass_manual.yaml](../blueprints/vm/blueprint_vm_storageclass_manual.yaml) | 1528 | 스토리지 클래스 수동 입력 변형 |
| [blueprints/cluster/blueprint_vra_cluster.yaml](../blueprints/cluster/blueprint_vra_cluster.yaml) | 230 | Kubernetes 게스트 클러스터 배포용 |
| [blueprints/archive/blueprint_vm_original.yaml](../blueprints/archive/blueprint_vm_original.yaml) | 921 | 이전 버전 백업 |

### Custom Form (YAML)
| 파일 | 라인 수 | 비고 |
| --- | --- | --- |
| [forms/vm/custom_vm.yml](../forms/vm/custom_vm.yml) | 1046 | 현재 VM 폼 (탭형) |
| [forms/vm/custom_vm_storageclass_manual.yml](../forms/vm/custom_vm_storageclass_manual.yml) | 1156 | 매뉴얼 스토리지 변형 |
| [forms/cluster/custom_cluster.yml](../forms/cluster/custom_cluster.yml) | 470 | 클러스터 폼 |
| [forms/archive/custom_vm_original.yml](../forms/archive/custom_vm_original.yml) | 358 | 이전 VM 폼 백업 |
| [forms/archive/custom_vra_cluster.yml](../forms/archive/custom_vra_cluster.yml) | 470 | `custom_cluster.yml`과 바이트 단위 동일 (중복) |

### vRO Scripts
- [actions/com.vmk/](../actions/com.vmk/) — REST 매니저 5종: `VraManager.js`, `VcsaManager.js`, `NsxtManager.js`, `ConfManager.js`, `TaskManager.js`. 각 매니저는 동일 디렉터리의 `*.png` 스크린샷과 짝.
- [actions/com.vmk.dk/](../actions/com.vmk.dk/) — 블루프린트 input `$data` / `$dynamicDefault`에 연결되는 데이터 제공 액션 및 헬퍼 스크립트 17종.

### Package
- [packages/com.dk.package](../packages/com.dk.package) — 서명된 vRO 패키지. 내부에 2개의 element + 인증서 포함.

## Blueprint Input ↔ vRO Action 연결 (확인된 매핑)

블루프린트가 `/data/vro-actions/com.vmk.dk/<name>` 경로로 참조하는 액션:
- `getProjectsNames` — VCFA 프로젝트 목록
- `getNamespaces` — 프로젝트별 네임스페이스
- `getVMClass` — VM Class 목록
- `getVMImage` — VM 이미지 목록 (`targetLibraryName` 파라미터)
- `getStorageClass` / `getStroageClassManual` / `getStroageClassManualOptionals` — 스토리지 클래스
- `getAdminUserByImage` — 이미지별 기본 OS admin 사용자

## 언어/문화 컨벤션

- 블루프린트/폼의 사용자 노출 텍스트(`title`, `description`)는 한국어 + 예시 포함.
- vRO 스크립트 주석/`System.log` 메시지는 한국어와 영어 혼용.

## 참고

- 디렉터리·데이터 흐름: [architecture.md](architecture.md)
- 보안: [security.md](security.md)
- 정리 대상: [tech-debt.md](tech-debt.md)
- 누적 작업 로그: [worklog.md](worklog.md)
- 런북: [runbooks/offline-setup.md](runbooks/offline-setup.md), [runbooks/deploy.md](runbooks/deploy.md)
