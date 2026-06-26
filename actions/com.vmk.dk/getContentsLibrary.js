// Return type: Array/Properties
// ★ 동적: Content Library = imageregistry.vmware.com 의 ClusterContentLibrary 'cl-' id
//   (= 블루프린트 content-library= 가 실제로 받는 형식. vCenter VAPI 의 UUID 아님).
//   흐름 (vRO host.createRestClient 로 CCI/proxy 직접 GET — 검증된 패턴):
//     1) CCI supervisornamespaces → 첫 namespace 의 URN
//        (metadata.annotations["infrastructure.cci.vmware.com/id"], 예: urn:vcloud:namespace:...)
//     2) /proxy/k8s/namespaces/<URN>/apis/imageregistry.vmware.com/v1alpha2/clustercontentlibraries
//   name = status.name (예: "Kubernetes Service"), id = metadata.name (예: cl-06403f0697ec9b5c6).
//   실패 시 폼이 안 깨지게 빈 목록 반환.

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getContentsLibrary] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

function cciGetJson(rest, path) {
  var req = rest.createRequest("GET", path, null);
  var resp = rest.execute(req);
  var code = resp.getStatusCode();
  if (code !== 200) { throw "HTTP " + code + " (" + path + ")"; }
  return JSON.parse(resp.getContentAsString());
}

try {
  var rest = host.createRestClient();

  // 1) namespace URN 얻기
  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) {
    System.warn("[getContentsLibrary] supervisornamespace 없음 — 빈 목록 반환");
    return [];
  }
  var meta = nsItems[0].metadata || {};
  var annot = meta.annotations || {};
  var urn = annot[URN_ANNOT];
  if (!urn) {
    System.warn("[getContentsLibrary] namespace URN(annotation " + URN_ANNOT + ") 없음 — 빈 목록 반환");
    return [];
  }

  // 2) ClusterContentLibrary (cl- id) 조회
  var path = "/proxy/k8s/namespaces/" + urn +
             "/apis/imageregistry.vmware.com/v1alpha2/clustercontentlibraries";
  var data = cciGetJson(rest, path);
  var libs = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var lib in libs) {
    var lmeta = lib.metadata || {};
    var lstatus = lib.status || {};
    var id = lmeta.name ? String(lmeta.name) : "";          // cl-...
    var name = lstatus.name ? String(lstatus.name) : id;     // 표시 이름
    if (!id || seen[id]) { continue; }
    seen[id] = true;

    var prop = new Properties();
    prop.put("name", name);
    prop.put("id", id);
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getContentsLibrary] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getContentsLibrary] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getContentsLibrary] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
