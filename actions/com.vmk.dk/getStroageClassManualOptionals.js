// Return type: Array/Properties
// ★ 동적: getStroageClassManual 과 동일하게 CCI 의 status.storageClasses[].name 을 합집합·중복제거하되,
//   맨 앞에 '(상속)' 항목을 추가(OS Disk 의 Storage Class 를 그대로 쓰는 fallback).
//   vRO 가 VCFA:Host REST 클라이언트로 CCI 직접 GET (검증된 패턴). 실패해도 최소 inherit 1개는 반환.

// ★ '__inherit__' 옵션 제거(2026-06-26): 카탈로그가 값(id)을 그대로 표시 → 폼 기본값 비움('')+placeholder.
//   블루프린트는 빈값을 '상속'으로 처리(!= '' && != '__inherit__'). "비워두면 OS Disk Storage Class 와 동일".
var CCI_PATH = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=500";

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getStroageClassManualOptionals] VCFA:Host 없음 — 빈 목록 반환");
  return results;
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var req = rest.createRequest("GET", CCI_PATH, null);
  var resp = rest.execute(req);
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getStroageClassManualOptionals] CCI GET HTTP=" + code + " — inherit 만 반환");
    return results;
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

  System.log("[getStroageClassManualOptionals] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getStroageClassManualOptionals] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getStroageClassManualOptionals] 오류 발생 — inherit 만 반환: " + e);
  return results;
}
