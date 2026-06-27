# Return type: string
# Inputs: TrustCA (string)
# ★ 동작: PEM 의 공백→'+' 복구 후 base64 를 **1회** 인코딩 → base64(PEM) 반환.
#   (이름 'doubleBase64' 는 레거시 — 실제로는 단일 base64. Secret 의 `data.*` 에 그대로 넣으면
#    소비자가 k8s 디코드 시 PEM 을 얻음. stringData 에 넣으면 k8s 가 한 겹 더 씌워 이중인코딩 버그 → 금지. [item7])
#   ★[2026-06-27 수정] 경계줄 보존을 CERTIFICATE 뿐 아니라 모든 PEM 타입으로 확장.
#    기존엔 'BEGIN CERTIFICATE' 만 헤더로 인식 → 개인키 '-----BEGIN PRIVATE KEY-----' 의 내부 공백이
#    '+' 로 치환돼 '-----BEGIN+PRIVATE+KEY-----' 로 깨짐 → kubernetes.io/tls Secret(HTTPS) 생성 실패.
#    이제 '-----BEGIN'/'-----END' 로 시작하는 줄은 종류(PRIVATE KEY/RSA PRIVATE KEY/EC/CERTIFICATE)와 무관히 원형 보존.
import base64
import hashlib

def _log_full(title: str, s: str, chunk: int = 2000):
    print(f"----- {title} (len={len(s)}) -----")
    for i in range(0, len(s), chunk):
        print(s[i:i+chunk])
    print(f"----- END {title} -----")

def handler(context, inputs):
    print("=== [Action Start] Base64 (Space Preservation Fix) ===")

    trust_ca = inputs.get("TrustCA")
    if not trust_ca:
        print("[WARN] TrustCA empty")
        return ""

    # [수정된 로직]
    # strip()을 쓰면 맨 앞의 '+'가 변한 공백이 삭제되므로, 
    # strip() 대신 줄바꿈만 제거하고 모든 공백을 '+'로 바꿉니다.

    lines = str(trust_ca).splitlines()
    fixed_lines = []
    
    for line in lines:
        # PEM 경계줄(-----BEGIN.../-----END...)은 종류 무관 원형 유지.
        #   개인키 'BEGIN PRIVATE KEY' 등 내부 공백이 '+' 로 치환되는 손상 방지.
        if line.strip().startswith("-----BEGIN") or line.strip().startswith("-----END"):
            fixed_lines.append(line)
        else:
            # 1. 줄바꿈 문자만 확실히 제거
            clean_line = line.replace("\r", "").replace("\n", "")
            
            # 2. 내용이 있는 경우에만 처리
            if clean_line:
                # 3. 모든 공백(Space)을 '+'로 치환 (맨 앞 공백 포함)
                restored_line = clean_line.replace(" ", "+")
                fixed_lines.append(restored_line)
    
    # 다시 하나의 문자열로 합침
    pem = "\n".join(fixed_lines)
    
    # 마지막 줄바꿈 보장
    if not pem.endswith("\n"):
        pem += "\n"

    # 복구된 결과 확인
    _log_full("INPUT_FIXED", pem)

    # 바이트 변환 및 해시 계산
    b = pem.encode("utf-8")
    sha256 = hashlib.sha256(b).hexdigest()
    
    print(f"[INFO] bytes_len={len(b)} sha256={sha256}")

    # Base64 인코딩
    out = base64.b64encode(b).decode("ascii")

    _log_full("BASE64_RESULT", out)

    return out