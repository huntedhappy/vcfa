// Return type: Array/Properties
// ★ 동적: getStorageClass 와 동일하게 CCI 의 status.storageClasses[].name 을 합집합·중복제거하되,
//   맨 앞에 '(상속)' 항목 추가(데이터 디스크가 OS Disk 의 Storage Class 를 그대로 쓰는 fallback).
//   기존 vCenter PBM 경로 + 하드코딩 'k8s'(가짜값) 제거, CCI 로 전환(2026-06-26). 실패해도 최소 inherit 1개는 반환.

var INHERIT_VALUE = "__inherit__";
var INHERIT_LABEL = "(상속) OS Disk Storage Class 사용";
var CCI_PATH = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=500";

var results = [];

// 항상 맨 앞에 inherit
var inheritProp = new Properties();
inheritProp.put("name", INHERIT_LABEL);
inheritProp.put("id", INHERIT_VALUE);
results.push(inheritProp);

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getStorageClassOptional] VCFA:Host 없음 — inherit 만 반환");
  return results;
}
var host = hosts[0];

try {
  var rest = host.createRestClient();
  var resp = rest.execute(rest.createRequest("GET", CCI_PATH, null));
  var code = resp.getStatusCode();
  if (code !== 200) {
    System.warn("[getStorageClassOptional] CCI GET HTTP=" + code + " — inherit 만 반환");
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

  System.log("[getStorageClassOptional] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getStorageClassOptional] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getStorageClassOptional] 오류 발생 — inherit 만 반환: " + e);
  return results;
}
