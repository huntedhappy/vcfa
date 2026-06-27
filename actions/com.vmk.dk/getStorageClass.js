// Inputs: ProjectName (string), NamespaceName (string)
// Return type: Array/Properties
// ★ 동적: *선택한 namespace 에 실현된* Storage Class = status.storageClasses[].name (CCI). getVMClass 와 동일 패턴(namespace scope).
//   path: /cci/.../infrastructure.cci.vmware.com/v1alpha3/namespaces/<project>/supervisornamespaces/<namespace>
//         → status.storageClasses[].name. vRO host.createRestClient 패턴(검증됨).
//   [item6, 2026-06-27] 기존 전체 namespace union → 선택 namespace scope. 선택 ns 에 없는 storageclass 는 노출하지 않음.
//   name=id=실제 스토리지클래스명(예: obcluster-vsan-storage-policy). 미선택/실패 시 빈 목록(폼 안 깨지게).

var BASE = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3";

var results = [];

if (!ProjectName || String(ProjectName) === "" || !NamespaceName || String(NamespaceName) === "") {
  System.log("[getStorageClass] ProjectName/NamespaceName 미선택 — 빈 목록(먼저 namespace 선택)");
  return [];
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getStorageClass] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var path = BASE + "/namespaces/" + ProjectName + "/supervisornamespaces/" + NamespaceName;
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getStorageClass] CCI GET HTTP=" + code + " (" + path + ") — 빈 목록 반환");
    return [];
  }

  var data = JSON.parse(resp.getContentAsString());
  var scs = (data.status && data.status.storageClasses) ? data.status.storageClasses : [];
  var seen = {};

  for each (var sc in scs) {
    var name = sc && sc.name ? String(sc.name) : "";
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

  System.log("[getStorageClass] " + ProjectName + "/" + NamespaceName + " → " + results.length + " storageClasses");
  for (var j = 0; j < results.length; j++) {
    System.log("[getStorageClass] " + results[j].get("name"));
  }
  return results;

} catch (e) {
  System.error("[getStorageClass] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
