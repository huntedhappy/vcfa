// Return type: Array/Properties
// ★ 동적: Storage Class = SupervisorNamespace 의 status.storageClasses[].name (CCI).
//   기존 vCenter PBM 경로는 9.x 에서 빈값 + 하드코딩 'k8s'(실재하지 않는 가짜값)만 노출됐음 → CCI 로 전환(2026-06-26).
//   vRO 가 VCFA:Host REST 클라이언트로 CCI 직접 GET (검증된 패턴, getStroageClassManual 과 동일).
//   모든 namespace 의 storageClasses 합집합·중복제거. name=id=실제 스토리지클래스명(예: obcluster-vsan-storage-policy).
//   실패 시 폼이 안 깨지게 빈 목록 반환.

var CCI_PATH = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=500";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getStorageClass] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var resp = rest.execute(rest.createRequest("GET", CCI_PATH, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getStorageClass] CCI GET HTTP=" + code + " — 빈 목록 반환");
    return [];
  }

  var data = JSON.parse(resp.getContentAsString());
  var items = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var ns in items) {
    var scs = (ns.status && ns.status.storageClasses) ? ns.status.storageClasses : [];
    for each (var sc in scs) {
      var name = sc && sc.name ? String(sc.name) : "";
      if (!name || seen[name]) { continue; }
      seen[name] = true;

      var prop = new Properties();
      prop.put("name", name);
      prop.put("id", name);
      results.push(prop);
    }
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getStorageClass] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getStorageClass] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getStorageClass] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
