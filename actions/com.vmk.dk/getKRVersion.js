// Inputs: ProjectName (string), NamespaceName (string)  ← 현재는 미사용(전 클러스터 KR 리소스 조회)
// Return type: Array/Properties
// ★ 동적: KR(Kubernetes Release) 버전 = 권위 소스 **KubernetesRelease** (kubernetes.vmware.com/v1alpha1/kubernetesreleases).
//   네이티브 클러스터 생성 폼이 KR Version 드롭다운에 쓰는 바로 그 리소스(= `kubectl get kr`).
//   ★ status Ready=True 인 것만(예 v1.35.0 은 ready=False → 제외해야 배포 실패 안 함).
//   value(id) = 클러스터 topology.version 포맷: spec.version 에서 끝의 '-vkr.N' 제거.
//     예 spec.version v1.35.2+vmware.1-vkr.3 → v1.35.2+vmware.1 (실배포 클러스터와 동일).
//   label(name) = 짧은 'vX.Y.Z'.
//   host.createRestClient → CCI/proxy 직접 GET (검증된 패턴). 실패 시 빈 목록.

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";
var KR_PATH = "/apis/kubernetes.vmware.com/v1alpha1/kubernetesreleases?limit=200";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getKRVersion] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

function cciGetJson(rest, path) {
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) { throw "HTTP " + code + " (" + path + ")"; }
  return JSON.parse(resp.getContentAsString());
}

function isReady(item) {
  var conds = (item.status && item.status.conditions) ? item.status.conditions : [];
  for each (var c in conds) {
    if (c && String(c.type) === "Ready") { return String(c.status) === "True"; }
  }
  return false;   // Ready 조건 없으면 미준비로 간주(보수적)
}

try {
  var rest = host.createRestClient();

  // namespace URN (cluster-scoped 리소스라도 proxy 경로엔 namespace URN 필요)
  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) { System.warn("[getKRVersion] supervisornamespace 없음"); return []; }
  var urn = ((nsItems[0].metadata || {}).annotations || {})[URN_ANNOT];
  if (!urn) { System.warn("[getKRVersion] namespace URN 없음"); return []; }

  var data = cciGetJson(rest, "/proxy/k8s/namespaces/" + urn + KR_PATH);
  var krs = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var kr in krs) {
    if (!isReady(kr)) { continue; }                       // ★ Ready=True 만
    var ver = (kr.spec && kr.spec.version) ? String(kr.spec.version) : "";   // 예 v1.35.2+vmware.1-vkr.3
    if (!ver) { continue; }
    var topo = ver.replace(/-vkr\.\d+$/, "");             // 끝 '-vkr.N' 제거 → v1.35.2+vmware.1
    if (seen[topo]) { continue; }
    seen[topo] = true;

    var m = topo.match(/^v\d+\.\d+\.\d+/);                // 짧은 vX.Y.Z (표시용)
    var label = m ? m[0] : topo;

    var prop = new Properties();
    prop.put("name", label);
    prop.put("id", topo);     // 전달 값 = topology.version 포맷
    results.push(prop);
  }

  // 버전 오름차순 정렬
  results.sort(function (a, b) {
    function parts(p) {
      var s = String(p.get("name")).replace(/^v/, "").split(".");
      return [parseInt(s[0], 10) || 0, parseInt(s[1], 10) || 0, parseInt(s[2], 10) || 0];
    }
    var pa = parts(a), pb = parts(b);
    for (var i = 0; i < 3; i++) { if (pa[i] !== pb[i]) { return pa[i] - pb[i]; } }
    return 0;
  });

  System.log("[getKRVersion] (kubernetesreleases, Ready만) results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getKRVersion] " + results[j].get("name") + " => " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getKRVersion] 오류 — 빈 목록 반환: " + e);
  return results;
}
