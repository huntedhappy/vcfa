// Return type: Array/Properties
// ★ 동적: 클러스터클래스 = cluster.x-k8s.io clusterclasses (vmware-system-vks-public) 중 builtin-generic-vX.Y.Z.
//   하드코딩(builtin-generic-v3.5.0) 대신 동적 — v3.6.0 등 새 버전이 나오면 드롭다운에 자동 노출(수동 변경 불필요).
//   host.createRestClient → supervisornamespace URN → /proxy/k8s/.../namespaces/vmware-system-vks-public/clusterclasses.
//   name=id=클래스명(예 builtin-generic-v3.6.0). 최신 버전 먼저(내림차순). 실패 시 빈 목록(폼 안 깨지게).

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";
var CC_PATH = "/apis/cluster.x-k8s.io/v1beta1/namespaces/vmware-system-vks-public/clusterclasses?limit=200";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getClusterClass] VCFA:Host 없음 — 빈 목록 반환");
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

  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) { System.warn("[getClusterClass] supervisornamespace 없음"); return []; }
  var urn = ((nsItems[0].metadata || {}).annotations || {})[URN_ANNOT];
  if (!urn) { System.warn("[getClusterClass] namespace URN 없음"); return []; }

  var data = cciGetJson(rest, "/proxy/k8s/namespaces/" + urn + CC_PATH);
  var items = (data && data.items) ? data.items : [];

  var names = [];
  for each (var cc in items) {
    var nm = ((cc.metadata || {}).name) ? String(cc.metadata.name) : "";
    if (/^builtin-generic-v\d+\.\d+\.\d+$/.test(nm)) { names.push(nm); }
  }

  // 버전 내림차순(최신 먼저)
  names.sort(function (a, b) {
    function ver(n) { var m = n.match(/v(\d+)\.(\d+)\.(\d+)/); return m ? [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)] : [0, 0, 0]; }
    var pa = ver(a), pb = ver(b);
    for (var i = 0; i < 3; i++) { if (pa[i] !== pb[i]) { return pb[i] - pa[i]; } }
    return 0;
  });

  for (var j = 0; j < names.length; j++) {
    var prop = new Properties();
    prop.put("name", names[j]);
    prop.put("id", names[j]);
    results.push(prop);
  }

  System.log("[getClusterClass] " + results.length + " clusterclasses");
  for (var k = 0; k < results.length; k++) { System.log("[getClusterClass] " + results[k].get("id")); }
  return results;

} catch (e) {
  System.error("[getClusterClass] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
