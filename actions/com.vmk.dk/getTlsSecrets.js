// Inputs: ProjectName (string), NamespaceName (string)
// Return type: Array/Properties  ({name,id} — getVMClass/getStorageClass 와 동일 포맷)
// ★ 동적: *선택한 namespace 의* kubernetes.io/tls Secret 목록 = HTTPS 인증서 후보.
//   VCFA UI(Gateway/HTTPS 설정)와 동일 경로: 네임스페이스 secret 리스트 → type=kubernetes.io/tls 필터.
//     ① CCI 로 supervisornamespace(ProjectName/NamespaceName) 조회 → URN(annotation infrastructure.cci.vmware.com/id)
//     ② /proxy/k8s/namespaces/<URN>/api/v1/namespaces/<NamespaceName>/secrets?limit=500
//        (getContentsLibrary/getOSSelector 와 동일한 proxy 패턴 — 검증됨)
//   name=id=Secret 이름. 미선택/실패/권한없음 시 빈 목록(폼 안 깨지게).

var CCI_BASE = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";
var TLS_TYPE = "kubernetes.io/tls";

var results = [];

if (!ProjectName || String(ProjectName) === "" || !NamespaceName || String(NamespaceName) === "") {
  System.log("[getTlsSecrets] ProjectName/NamespaceName 미선택 — 빈 목록(먼저 namespace 선택)");
  return [];
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getTlsSecrets] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

function cciGetJson(rest, path) {
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) { throw "HTTP " + code + " (" + path + ")"; }
  return JSON.parse(resp.getContentAsString());
}

try {
  var rest = host.createRestClient();

  // ① 선택한 supervisornamespace 의 URN 조회
  var nsPath = CCI_BASE + "/namespaces/" + ProjectName + "/supervisornamespaces/" + NamespaceName;
  var nsObj = cciGetJson(rest, nsPath);
  var urn = ((nsObj.metadata || {}).annotations || {})[URN_ANNOT];
  if (!urn) {
    System.warn("[getTlsSecrets] URN(" + URN_ANNOT + ") 없음 (" + nsPath + ") — 빈 목록 반환");
    return [];
  }

  // ② proxy 로 네임스페이스 secret 리스트 → kubernetes.io/tls 만
  var secPath = "/proxy/k8s/namespaces/" + urn + "/api/v1/namespaces/" + NamespaceName + "/secrets?limit=500";
  var data = cciGetJson(rest, secPath);
  var items = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var s in items) {
    if (!s || String(s.type) !== TLS_TYPE) { continue; }
    var name = ((s.metadata || {}).name) ? String(s.metadata.name) : "";
    if (!name || seen[name]) { continue; }
    seen[name] = true;

    var prop = new Properties();
    prop.put("name", name);
    prop.put("id", name);
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getTlsSecrets] " + ProjectName + "/" + NamespaceName + " → " + results.length + " TLS secrets");
  for (var j = 0; j < results.length; j++) {
    System.log("[getTlsSecrets] " + results[j].get("name"));
  }
  return results;

} catch (e) {
  System.error("[getTlsSecrets] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
