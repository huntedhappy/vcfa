// Inputs: ProjectName (string), NamespaceName (string)
// Return type: Array/Properties
// ★ 동적: getStorageClass 와 동일 — *선택한 namespace* 의 status.storageClasses[].name (CCI, namespace scope).
//   데이터 디스크용. 비워두면 OS Disk Storage Class 와 동일(블루프린트가 '' 를 상속으로 처리).
//   [item6, 2026-06-27] 전체 union → 선택 namespace scope (getVMClass 패턴). 미선택/실패 시 빈 목록.

var BASE = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3";

var results = [];

if (!ProjectName || String(ProjectName) === "" || !NamespaceName || String(NamespaceName) === "") {
  System.log("[getStorageClassOptional] ProjectName/NamespaceName 미선택 — 빈 목록(먼저 namespace 선택)");
  return results;
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getStorageClassOptional] VCFA:Host 없음 — 빈 목록 반환");
  return results;
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var path = BASE + "/namespaces/" + ProjectName + "/supervisornamespaces/" + NamespaceName;
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getStorageClassOptional] CCI GET HTTP=" + code + " (" + path + ") — 빈 목록 반환");
    return results;
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

  // [item2] "비움 = OS Disk Storage Class 사용" 옵션을 맨 앞에 (id='').
  //   빈값('')이 카탈로그 드롭다운의 유효 값이 되어, data disk storage 미지정 배포의
  //   "'' is not an acceptable value" 400 을 방지. 블루프린트는 '' 를 상속(OS Disk)으로 처리.
  var inh = new Properties();
  inh.put("name", "(비움 = OS Disk Storage Class 사용)");
  inh.put("id", "");
  results.unshift(inh);

  System.log("[getStorageClassOptional] " + ProjectName + "/" + NamespaceName + " → " + results.length + " storageClasses");
  for (var j = 0; j < results.length; j++) {
    System.log("[getStorageClassOptional] " + results[j].get("name"));
  }
  return results;

} catch (e) {
  System.error("[getStorageClassOptional] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
