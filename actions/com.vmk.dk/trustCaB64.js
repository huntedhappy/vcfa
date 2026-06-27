# Return type: string
# Inputs: TrustCA (string)
# ★ 트러스트 CA(클러스터 additionalTrustedCAs) 전용: PEM 공백→'+' 복구 후 base64 를 **2회(double)** →
#   base64(base64(PEM)) 반환. VKS 의 osConfiguration.trust.additionalTrustedCAs.secretRef 소비자가
#   k8s data 디코드(1회) 후 내부적으로 한 번 더 디코드하므로 **이중 인코딩**이 필요(2026-06-27 E2E 확정:
#   single 이면 클러스터가 노드 생성 못 하고 영구 INPROGRESS, double 이면 ~2분 내 컨트롤플레인 노드 생성).
#   ※ HTTPS kubernetes.io/tls Secret 은 단일 base64(doubleBase64.js) — 소비자(k8s tls)가 1회만 디코드하므로
#     둘은 분리한다. 이름 'doubleBase64' 가 실제로는 single 이라 트러스트 CA 에 잘못 쓰여 깨졌던 것을 분리 수정.
import base64

def handler(context, inputs):
    trust_ca = inputs.get("TrustCA")
    if not trust_ca:
        return ""
    lines = str(trust_ca).splitlines()
    fixed = []
    for line in lines:
        # PEM 경계줄(-----BEGIN.../-----END...)은 종류 무관 원형 유지(개인키 등 내부 공백 손상 방지).
        if line.strip().startswith("-----BEGIN") or line.strip().startswith("-----END"):
            fixed.append(line)
        else:
            clean = line.replace("\r", "").replace("\n", "")
            if clean:
                fixed.append(clean.replace(" ", "+"))
    pem = "\n".join(fixed)
    if not pem.endswith("\n"):
        pem += "\n"
    once = base64.b64encode(pem.encode("utf-8")).decode("ascii")     # base64(PEM)
    twice = base64.b64encode(once.encode("ascii")).decode("ascii")   # base64(base64(PEM)) ← VKS 가 두 번 디코드
    return twice
