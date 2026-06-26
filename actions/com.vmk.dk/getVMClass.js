// Inputs: ProjectName (string), NamespaceName (string)
// Return type: Array/Properties
// ★ 동적: *선택한 namespace 에 실제 할당/실현된* VM class (status.vmClasses) 만 반환.
//   region 전체가 아니라 namespace 범위 — 그 namespace 에 없는 클래스를 고르면 클러스터 생성이 실패하므로.
//   namespace 미선택이면 빈 목록(먼저 project/namespace 를 골라야 함 — getKRVersion 과 동일 의존).
//   path: /cci/.../infrastructure.cci.vmware.com/v1alpha3/namespaces/<project>/supervisornamespaces/<namespace>
//         → status.vmClasses[].name. vRO host.createRestClient 패턴(검증됨).

var BASE = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3";

var results = [];

if (!ProjectName || String(ProjectName) === "" || !NamespaceName || String(NamespaceName) === "") {
  System.log("[getVMClass] ProjectName/NamespaceName 미선택 — 빈 목록(먼저 namespace 선택)");
  return [];
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getVMClass] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var path = BASE + "/namespaces/" + ProjectName + "/supervisornamespaces/" + NamespaceName;
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getVMClass] CCI GET HTTP=" + code + " (" + path + ") — 빈 목록 반환");
    return [];
  }

  var data = JSON.parse(resp.getContentAsString());
  var vmClasses = (data.status && data.status.vmClasses) ? data.status.vmClasses : [];
  var seen = {};

  for each (var c in vmClasses) {
    var name = (c && c.name) ? String(c.name) : "";
    if (!name || seen[name]) { continue; }
    seen[name] = true;

    var prop = new Properties();
    prop.put("name", name);   // UI 표시 = 클래스명
    prop.put("id", name);     // 전달 값 = 클래스명
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("id")), bn = String(b.get("id"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getVMClass] " + ProjectName + "/" + NamespaceName + " → " + results.length + " classes");
  for (var j = 0; j < results.length; j++) {
    System.log("[getVMClass] " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getVMClass] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
