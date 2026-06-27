#!/usr/bin/env bash
# ============================================================
# win2025-customize.sh — VCFA Windows Server 2025 배포 후처리 (guest-ops)
# ------------------------------------------------------------
# 왜 필요한가: Windows 2025 는 vSphere GOSC(Sysprep)가 OOBE locale/hide 를 못 잡아 "Hi there" 에서
#   멈춘다(=vm-operator bootstrap.sysprep 도 같은 GOSC 엔진이라 동일 실패, Administrator 가 망가짐).
#   그래서 Windows 블루프린트(blueprint_vm_win_2025.yaml)는 2025 용으로 **bootstrap 을 빼고**(no-bootstrap)
#   배포한다 → 템플릿 Administrator(빌드비번)가 보존된다. 이 스크립트가 배포 후 VMware Tools guest-ops 로
#   비번/정적IP/호스트명/RDP 를 직접 설정한다. (= /var/tmp/ad 의 guestinfo+firstboot 와 동일 원리, E2E 검증.)
#
# 사용: scripts/win2025-customize.sh <hostname> <new-admin-pass> <static-ip> [gateway] [prefix] [dns] [auth-pass]
#   - <hostname>       : VM 이름 prefix(=배포 시 hostname). govc 로 해당 VM 을 찾는다.
#   - <new-admin-pass> : 설정할 Administrator 비밀번호
#   - <static-ip>      : 게스트에 넣을 정적 IP (대역에서 빈 IP — no-bootstrap 라 IPAM 예약 안 됨, ping 으로 확인)
#   - gateway/prefix/dns : 기본 172.28.0.65 / 27 / 10.253.100.2
#   - auth-pass        : guest-ops 인증 비번. 기본 = .env.tenant 의 WIN_BUILD_PASSWORD(=Windows 템플릿을 빌드할 때
#                        정한 Administrator 비번 — 환경/템플릿마다 다름, 하드코딩 없음). 이미 커스터마이즈된 VM 을
#                        다시 손볼 땐 7번째 인자로 현재 비번을 넘긴다.
# 전제: .env.tenant 의 VC_HOST/VC_USER/VC_PASS (govc), 대상 VM 이 no-bootstrap 으로 배포돼 guestOpsReady=true.
# ============================================================
set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
set -a; . ./.env.tenant; set +a
export GOVC_URL="https://${VC_USER}:${VC_PASS}@${VC_HOST}" GOVC_INSECURE=1

HOST="${1:?Usage: <hostname> <new-pass> <static-ip> [gw] [prefix] [dns] [auth-pass]}"
NEWPASS="${2:?new admin password required}"
IP="${3:?static ip required}"
GW="${4:-172.28.0.65}"; PREFIX="${5:-27}"; DNS="${6:-10.253.100.2}"
AUTHPASS="${7:-${WIN_BUILD_PASSWORD:-}}"
[ -z "$AUTHPASS" ] && { echo "ERROR: 인증 비번 없음 — .env.tenant 에 WIN_BUILD_PASSWORD(Windows 템플릿 빌드 Administrator 비번) 설정,"; echo "       또는 7번째 인자로 현재 비번 전달. (하드코딩 제거 — 환경별 값)"; exit 1; }
HOSTUP=$(printf '%s' "$HOST" | tr 'a-z' 'A-Z')
DOIIS="${WIN_INSTALL_IIS:-0}"   # WIN_INSTALL_IIS=1 → IIS(Web-Server) 설치. 블루프린트 enableIis=true 와 함께 쓰면 web LB(80) 로 노출(Linux nginx 대응).

VM=$(govc find / -type m -name "${HOST}*" 2>/dev/null | head -1)
[ -z "$VM" ] && { echo "ERROR: VM 없음: ${HOST}*"; exit 1; }
echo "VM=$VM"
echo "  → host=$HOST  ip=$IP/$PREFIX  gw=$GW  dns=$DNS"

read -r -d '' PS <<PSEOF
\$ErrorActionPreference='Continue'
\$log='C:\\ProgramData\\DThub\\customize.log'
New-Item -ItemType Directory -Force -Path 'C:\\ProgramData\\DThub' | Out-Null
function L(\$m){ Add-Content -Path \$log -Value (('[{0:u}] {1}' -f (Get-Date),\$m)) }
L 'win2025 customize start'
# 1) Administrator 활성 + 새 비번
Enable-LocalUser -Name 'Administrator' -ErrorAction SilentlyContinue
\$sec=ConvertTo-SecureString '${NEWPASS}' -AsPlainText -Force
Set-LocalUser -Name 'Administrator' -Password \$sec -PasswordNeverExpires \$true -ErrorAction SilentlyContinue
L 'password set'
# 2) 정적 IP — ★DHCP 를 먼저 끈다(안 끄면 DHCP 가 정적을 덮어 APIPA 로 되돌림; 이 망은 DHCP 서버 없음)
\$a=Get-NetAdapter -Physical | Where-Object {\$_.Status -eq 'Up'} | Select-Object -First 1
if(-not \$a){ \$a=Get-NetAdapter | Where-Object {\$_.HardwareInterface} | Select-Object -First 1 }
Set-NetIPInterface -InterfaceIndex \$a.ifIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction SilentlyContinue
Get-NetIPAddress -InterfaceIndex \$a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {\$_.IPAddress -ne '127.0.0.1'} | Remove-NetIPAddress -Confirm:\$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex \$a.ifIndex -AddressFamily IPv4 -Confirm:\$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex \$a.ifIndex -IPAddress '${IP}' -PrefixLength ${PREFIX} -DefaultGateway '${GW}' -ErrorAction SilentlyContinue | Out-Null
Set-DnsClientServerAddress -InterfaceIndex \$a.ifIndex -ServerAddresses @('${DNS}') -ErrorAction SilentlyContinue
L 'static ip set'
# 3) RDP 활성(+방화벽)
Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name fDenyTSConnections -Value 0 -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
L 'rdp enabled'
# 3.5) IIS 웹서버 (WIN_INSTALL_IIS=1 일 때만 — Linux 의 nginx 대응). web LB(80)는 블루프린트 enableIis 가 노출.
if('${DOIIS}' -eq '1'){ Install-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null; New-Item -ItemType Directory -Force -Path 'C:\\inetpub\\wwwroot' | Out-Null; Set-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<html><body><h1>${HOST} - IIS on VCFA</h1></body></html>' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'HTTP-In-80' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -ErrorAction SilentlyContinue | Out-Null; L 'iis installed' }
# 4) 호스트명 + reboot(호스트명/네트워크 확정)
if(\$env:COMPUTERNAME -ne '${HOSTUP}'){ Rename-Computer -NewName '${HOST}' -Force -ErrorAction SilentlyContinue; L 'renamed' }
L 'done; rebooting'
Start-Sleep -Seconds 2
Restart-Computer -Force
PSEOF
ENC=$(printf '%s' "$PS" | iconv -t UTF-16LE | base64 -w0)

echo "=== guest-ops 실행 (인증=${AUTHPASS:0:3}***) ==="
govc guest.start -vm "$VM" -l "Administrator:${AUTHPASS}" \
  'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$ENC" \
  && echo "  ✓ 실행 시작됨" || { echo "  ✗ 인증/실행 실패 — WIN_BUILD_PASSWORD(템플릿 빌드비번) 또는 현재 비번 확인"; exit 2; }
echo "  → ~2-3분 reboot 후: host=${HOST}, ip=${IP}, Administrator 새 비번, RDP 활성."
echo "  접속: VCFA UI 의 RDP LoadBalancer VIP 로 RDP (또는 ${IP}:3389 직접)."
