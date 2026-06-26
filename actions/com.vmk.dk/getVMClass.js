// Return type: Array/Properties
// ★ 동적: VM Class = SupervisorNamespace 의 status.vmClasses[].name (CCI). 하드코딩 제거.
//   vRO 가 VCFA:Host 의 REST 클라이언트로 CCI 를 직접 GET (검증된 패턴):
//     host.createRestClient() → createRequest("GET", path, null) → execute() → getContentAsString()
//   폼에서 파라미터(project/namespace)를 안 주므로, 모든 namespace 의 vmClasses 를 합집합·중복제거.
//   name=id=클래스명(예: best-effort-large). 실패 시 폼이 안 깨지게 빈 목록 반환.

var CCI_PATH = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=500";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getVMClass] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var req = rest.createRequest("GET", CCI_PATH, null);
  var resp = rest.execute(req);
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getVMClass] CCI GET HTTP=" + code + " — 빈 목록 반환");
    return [];
  }

  var data = JSON.parse(resp.getContentAsString());
  var items = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var ns in items) {
    var vmClasses = (ns.status && ns.status.vmClasses) ? ns.status.vmClasses : [];
    for each (var c in vmClasses) {
      var name = c && c.name ? String(c.name) : "";
      if (!name || seen[name]) { continue; }
      seen[name] = true;

      var prop = new Properties();
      prop.put("name", name);   // UI 표시
      prop.put("id", name);     // 전달 값(=클래스명)
      results.push(prop);
    }
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getVMClass] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getVMClass] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getVMClass] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
