// 입력: krVersion (string) — getKRVersion 의 값(예: "v1.35.2---vmware.1-vkr.3"). role (string, optional) — "worker"면 windows 포함, 그 외엔 제외(control plane).
// Return type: Array/Properties
// ★ 네이티브 클러스터 UI 의 "OS Image" 드롭다운 재현: 선택한 KR 버전에 있는 OS 이미지만, "Ubuntu 22.04 - Kubernetes Service" 라벨.
//   소스 = run.tanzu.vmware.com/v1alpha3/osimages (OSImage). 라벨에 os-name/os-version/content-library/kubernetesVersion 보유.
//   라이브러리명(Kubernetes Service / Custom Kubernetes Service)은 imageregistry clustercontentlibraries 의 cl- → status.name 으로 매핑.
//   value(id) = 블루프린트가 그대로 쓰는 resolve-os-image 셀렉터: "os-name=<os>, content-library=<cl>[, os-version=<ver>]".
//   join: getKRVersion 값에서 끝의 '-vkr.N' 을 떼면 OSImage 의 kubernetesVersion 라벨과 일치(예 v1.35.2---vmware.1-vkr.3 → v1.35.2---vmware.1).
//   windows 는 worker 노드 전용 → role!="worker" 이면 제외. 실패 시 폼이 안 깨지게 빈 목록.

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";

var results = [];

var krIn = String(krVersion || "").trim();
if (krIn === "") {
  System.warn("[getOSImageByKR] krVersion 비어있음 — 먼저 KR 버전 선택. 빈 목록 반환");
  return [];
}
var krKey = krIn.replace(/-vkr\.\d+$/, "");   // OSImage kubernetesVersion 라벨과 매칭할 키
var wantWorker = (String(role || "").toLowerCase() === "worker");

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getOSImageByKR] VCFA:Host 없음 — 빈 목록 반환");
  return [];
}
var host = hosts[0];

function cciGetJson(rest, path) {
  var resp = rest.execute(rest.createRequest("GET", path, null));
  var code = resp.getStatusCode();
  if (code !== 200) { throw "HTTP " + code + " (" + path + ")"; }
  return JSON.parse(resp.getContentAsString());
}

function osFriendly(osName, osVer) {
  var n = String(osName || "").toLowerCase();
  var major = String(osVer || "").split(".")[0];   // photon "5"/"5.0"→"5", rhel "9"
  if (n === "ubuntu") { return "Ubuntu " + osVer; }          // 22.04 / 24.04
  if (n === "photon") { return "Photon " + major; }          // 5
  if (n === "rhel")   { return "Rhel " + major; }            // 9
  if (n.indexOf("windows") >= 0) { return "Windows " + osVer; }
  return String(osName) + " " + String(osVer);
}

try {
  var rest = host.createRestClient();

  // 1) namespace URN
  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) { System.warn("[getOSImageByKR] supervisornamespace 없음"); return []; }
  var urn = ((nsItems[0].metadata || {}).annotations || {})[URN_ANNOT];
  if (!urn) { System.warn("[getOSImageByKR] namespace URN 없음"); return []; }
  var P = "/proxy/k8s/namespaces/" + urn;

  // 2) cl- id → 라이브러리명 맵
  var libMap = {};
  try {
    var ccl = cciGetJson(rest, P + "/apis/imageregistry.vmware.com/v1alpha2/clustercontentlibraries");
    for each (var lib in (ccl.items || [])) {
      var lid = (lib.metadata || {}).name;
      var lname = (lib.status || {}).name;
      if (lid) { libMap[String(lid)] = lname ? String(lname) : String(lid); }
    }
  } catch (eLib) { System.warn("[getOSImageByKR] 라이브러리명 매핑 실패(계속): " + eLib); }

  // 3) OSImage 조회 → KR 필터 → 라벨/값 구성
  var data = cciGetJson(rest, P + "/apis/run.tanzu.vmware.com/v1alpha3/osimages?limit=500");
  var imgs = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var img in imgs) {
    var L = (img.metadata || {}).labels || {};
    var k8s = L["run.tanzu.vmware.com/kubernetesVersion"];
    if (!k8s || String(k8s) !== krKey) { continue; }   // 선택한 KR 버전만

    var osName = L["os-name"], osVer = L["os-version"], osType = L["os-type"] || "";
    var clId = L["content-library"];
    if (!osName || !clId) { continue; }

    var isWindows = (String(osType).toLowerCase().indexOf("windows") >= 0) || (String(osName).toLowerCase().indexOf("windows") >= 0);
    if (isWindows && !wantWorker) { continue; }        // windows 는 worker 전용

    var libName = libMap[String(clId)] || String(clId);
    var label = osFriendly(osName, osVer) + " - " + libName;
    if (seen[label]) { continue; }
    seen[label] = true;

    // resolve-os-image 셀렉터 (블루프린트가 그대로 사용). ubuntu 만 os-version 포함(22.04/24.04 구분).
    var sel = "os-name=" + osName + ", content-library=" + clId;
    if (String(osName).toLowerCase() === "ubuntu") { sel += ", os-version=" + osVer; }

    var prop = new Properties();
    prop.put("name", label);
    prop.put("id", sel);
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getOSImageByKR] krVersion=" + krIn + " (key=" + krKey + ") role=" + (wantWorker?"worker":"controlplane") + " → " + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getOSImageByKR] " + results[j].get("name") + "  ||  " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getOSImageByKR] 오류 — 빈 목록 반환: " + e);
  return results;
}
