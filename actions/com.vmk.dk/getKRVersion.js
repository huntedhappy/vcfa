// Inputs: ProjectName (string), NamespaceName (string)  ← 현재는 미사용(전 클러스터 이미지에서 직접 추출)
// Return type: Array/Properties
// ★ 동적: KR(Kubernetes Release) 버전 = Supervisor ClusterVirtualMachineImage 의 status.name 에 들어있는 vkr 버전 문자열.
//   이름 예: ob-25217799-ubuntu-2404-amd64-v1.35.0---vmware.2-vkr.4
//     → 'vX.Y.Z---vmware.N[-fips]-vkr.M' 패턴 추출·중복제거(같은 KR 이 ubuntu/photon 여러 이미지에 중복).
//   label(name) = 'vX.Y.Z'(짧은 버전, 드롭다운 표시),
//   value(id)   = 전체 'vX.Y.Z---vmware.N[-fips]-vkr.M'(시스템 전달값).
//   ★ 2026-06-26 VAPIManager(콘텐츠 라이브러리 스캔)→CCI 로 이전. 결과는 기존과 동일(라이브 8개 일치 검증).
//     getVMImage.js 와 동일한 host.createRestClient → CCI 프록시 clustervirtualmachineimages 패턴.
//   실패 시 폼이 안 깨지게 빈 목록 반환.

var KR_RE = /v\d+\.\d+\.\d+---vmware\.\d+(?:-fips)?-vkr\.\d+/;   // status.name 에서 KR 버전 추출
var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";
var CVMI_VERSIONS = ["v1alpha3", "v1alpha2"];

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getKRVersion] VCFA:Host 없음 — 빈 목록 반환");
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

  // 1) namespace URN 얻기 (cluster-scoped 리소스라도 proxy 경로엔 namespace URN 이 필요)
  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) {
    System.warn("[getKRVersion] supervisornamespace 없음 — 빈 목록 반환");
    return [];
  }
  var meta = nsItems[0].metadata || {};
  var annot = meta.annotations || {};
  var urn = annot[URN_ANNOT];
  if (!urn) {
    System.warn("[getKRVersion] namespace URN(annotation " + URN_ANNOT + ") 없음 — 빈 목록 반환");
    return [];
  }

  // 2) ClusterVirtualMachineImage 조회 (v1alpha3 우선, 실패 시 v1alpha2)
  var data = null;
  for each (var ver in CVMI_VERSIONS) {
    var path = "/proxy/k8s/namespaces/" + urn +
               "/apis/vmoperator.vmware.com/" + ver + "/clustervirtualmachineimages";
    try {
      data = cciGetJson(rest, path);
      System.log("[getKRVersion] " + ver + " OK");
      break;
    } catch (eVer) {
      System.warn("[getKRVersion] " + ver + " 실패: " + eVer);
      data = null;
    }
  }
  if (!data) {
    System.warn("[getKRVersion] clustervirtualmachineimages 조회 실패(모든 버전) — 빈 목록 반환");
    return [];
  }

  var imgs = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var img in imgs) {
    var istatus = img.status || {};
    var nm = istatus.name ? String(istatus.name) : "";
    if (!nm) { continue; }
    var m = nm.match(KR_RE);
    if (!m) { continue; }

    var full = m[0];
    if (seen[full]) { continue; }
    seen[full] = true;

    var label = full.substring(0, full.indexOf("---"));   // vX.Y.Z
    var prop = new Properties();
    prop.put("name", label);
    prop.put("id", full);
    results.push(prop);
  }

  // 버전 오름차순 정렬 (label 의 major.minor.patch 숫자 기준)
  results.sort(function (a, b) {
    function parts(p) {
      var s = String(p.get("name")).replace(/^v/, "").split(".");
      return [parseInt(s[0], 10) || 0, parseInt(s[1], 10) || 0, parseInt(s[2], 10) || 0];
    }
    var pa = parts(a), pb = parts(b);
    for (var i = 0; i < 3; i++) { if (pa[i] !== pb[i]) { return pa[i] - pb[i]; } }
    return 0;
  });

  System.log("[getKRVersion] results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getKRVersion] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getKRVersion] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
