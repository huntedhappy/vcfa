// Inputs: ProjectName (string), NamespaceName (string)
// Return type: Array/Properties
// ★ getVMClass 와 동일(선택 namespace 의 status.vmClasses) + 맨 앞에 "비움" 옵션(id='').
//   조건부 입력(예 NodePool 2 vmclass)이 비활성 시 숨겨진 채 '' 로 제출돼도 카탈로그가 거부("'' is not an
//   acceptable value")하지 않도록 빈값을 유효 옵션으로 제공. 활성 시 사용자가 실제 클래스를 선택.
//   [2026-06-27] getStorageClassOptional 과 같은 패턴.

var BASE = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3";

var results = [];

if (!ProjectName || String(ProjectName) === "" || !NamespaceName || String(NamespaceName) === "") {
  System.log("[getVMClassOptional] ProjectName/NamespaceName 미선택 — 빈 목록(먼저 namespace 선택)");
  return [];
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getVMClassOptional] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var path = BASE + "/namespaces/" + ProjectName + "/supervisornamespaces/" + NamespaceName;
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getVMClassOptional] CCI GET HTTP=" + code + " (" + path + ") — 빈 목록 반환");
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
    prop.put("name", name);
    prop.put("id", name);
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("id")), bn = String(b.get("id"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  // [item] "비움" 옵션을 맨 앞에 (id='') — 조건부 비활성 시 빈값이 유효해져 배포 400 방지.
  var inh = new Properties();
  inh.put("name", "(비움 = 미사용)");
  inh.put("id", "");
  results.unshift(inh);

  System.log("[getVMClassOptional] " + ProjectName + "/" + NamespaceName + " → " + results.length + " (inherit 포함)");
  return results;

} catch (e) {
  System.error("[getVMClassOptional] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
