# Architecture

> 현재 리포에서 **직접 확인된** 파일 구조와 연결 관계만 기록합니다.

## 디렉터리 레이아웃

```
.
├── README.md                              # 개요 + 사용법 (간단)
├── .gitignore                             # .ssh/ 제외
├── blueprints/                            # Cloud Assembly 블루프린트
│   ├── vm/
│   │   ├── blueprint_vm.yaml
│   ├── cluster/
│   │   └── blueprint_vra_cluster.yaml
│   └── archive/
│       └── blueprint_vm_original.yaml
├── forms/                                 # Service Broker 커스텀 폼
│   ├── vm/
│   │   ├── custom_vm.yml
│   ├── cluster/
│   │   └── custom_cluster.yml
│   └── archive/
│       ├── custom_vm_original.yml
│       └── custom_vra_cluster.yml         # custom_cluster.yml과 동일
├── actions/                               # vRO 스크립트 (모듈명과 폴더명 일치)
│   ├── com.vmk/                           # REST 매니저
│   │   ├── VraManager.js  + VraManager.png
│   │   ├── VcsaManager.js + VcsaManager.png
│   │   ├── NsxtManager.js + NsxtManager.png
│   │   ├── ConfManager.js + ConfManager.png
│   │   └── TaskManager.js + TaskManager.png
│   └── com.vmk.dk/                        # 데이터/헬퍼 액션
│       ├── getProjectsNames.js
│       ├── getNameSpaces.js
│       ├── getVMClass.js
│       ├── getVMImage.js
│       ├── getStorageClass.js
│       ├── getStorageClassOptional.js
│       ├── getStroageClassManual.js
│       ├── getStroageClassManualOptionals.js
│       ├── getAdminUserByImage.js
│       ├── getContentsLibrary.js
│       ├── getKRVersion.js
│       ├── getOS.js
│       ├── getUbuntuVersion.js
│       ├── ChangePasswordHash.js           # 실체 Python (crypt SHA-512)
│       ├── validatePasswordMatch.js
│       ├── doubleBase64.js
│       └── dumpVcRoots.js
├── packages/
│   └── com.dk.package                     # 서명된 vRO 패키지 (zip)
└── docs/
    ├── context.md
    ├── architecture.md (이 파일)
    ├── security.md
    ├── tech-debt.md
    ├── worklog.md
    └── runbooks/
        ├── offline-setup.md
        └── deploy.md
```

## 컴포넌트 책임

### Blueprint (Cloud Assembly)
- 사용자 입력(`inputs:`), 리소스 토폴로지(`resources:`)와 cloud-init 로직.
- 입력의 동적 옵션은 `$data: /data/vro-actions/com.vmk.dk/<action>`로 vRO 액션 호출.
- **로컬 경로가 아닌 URL 기준**이라 본 리포의 폴더 재배치는 블루프린트 동작에 영향 없음.

### Custom Form (Service Broker)
- 동일한 블루프린트 input들을 UI 페이지/섹션/탭으로 재배열.
- 한 블루프린트당 하나의 폼이 1:1로 짝지어집니다 (매핑은 [runbooks/deploy.md](runbooks/deploy.md) 2-3절).

### vRO Managers (`actions/com.vmk/`)
- `VraManager.js`: `VraHostManager.findHostsByType("vra-onprem")`로 호스트를 찾아 REST 클라이언트 생성, GET/POST 헬퍼 노출.
- 나머지 매니저(`Vcsa`/`Nsxt`/`Conf`/`Task`)도 동일 패턴의 REST 래퍼.

### vRO Actions (`actions/com.vmk.dk/`)
- Cloud Assembly input 드롭다운/기본값에 데이터 공급.
- 단순 조회(`getProjectsNames`)와 파라미터 기반 조회(`getNamespaces?ProjectName=...`) 혼재.
- `ChangePasswordHash.js`는 Python 액션 — 평문 → `$6$` SHA-512 해시.

### vRO Package
- `packages/com.dk.package`는 zip 컨테이너 안에 element 2개 + 인증서 + 서명 포함.

## 데이터 흐름 (확인된 부분)

```
사용자
  │  Service Broker UI (forms/**)
  ▼
Cloud Assembly Blueprint (blueprints/**)
  │  $data / $dynamicDefault
  ▼
vRO Action (actions/com.vmk.dk/*.js)
  │  매니저 호출
  ▼
vRO Manager (actions/com.vmk/*.js)
  │  REST
  ▼
VCFA / VCSA / NSX-T / Aria Automation
```
