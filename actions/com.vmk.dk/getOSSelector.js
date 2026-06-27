// 입력: osImage (string, 친근 라벨 예 "Ubuntu 22.04 - Kubernetes Service"), krVersion (string), role (string)
// Return type: string  (= resolve-os-image 셀렉터)
// ★ getOSImageByKR 가 드롭다운에 *친근 라벨* 을 노출하므로(카탈로그가 값을 그대로 표시),
//   블루프린트가 쓸 실제 resolve-os-image 셀렉터는 이 액션이 라벨→셀렉터로 변환해 준다(숨김 $dynamicDefault 필드용).
//   getOSImageByKR 와 동일한 OSImage 쿼리·필터·라벨 구성 → 라벨이 일치하는 항목의 셀렉터를 반환.
//   못 찾으면 빈 문자열("") 반환(블루프린트에서 분기/검증 가능).

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";

var want = String(osImage || "").trim();
var krIn = String(krVersion || "").trim();
if (want === "" || krIn === "") {
  System.warn("[getOSSelector] osImage/krVersion 비어있음 — '' 반환");
  return "";
}
var krKey = krIn.replace("+", "---").replace(" ", "---").replace(/-vkr\.\d+$/, "");
// [item2] 폼 리터럴 바인딩('`worker`')의 백틱/공백이 섞여 와도 안전하게 정규화(엔진 동작 무관).
var wantWorker = (String(role || "").toLowerCase().replace(/`/g, "").replace(/\s+/g, "") === "worker");

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) { System.warn("[getOSSelector] VCFA:Host 없음 — '' 반환"); return ""; }
var host = hosts[0];

function cciGetJson(rest, path) {
  var resp = rest.execute(rest.createRequest("GET", path, null));
  if (resp.getStatusCode() !== 200) { throw "HTTP " + resp.getStatusCode() + " (" + path + ")"; }
  return JSON.parse(resp.getContentAsString());
}
function osFriendly(osName, osVer) {
  var n = String(osName || "").toLowerCase();
  var major = String(osVer || "").split(".")[0];
  if (n === "ubuntu") { return "Ubuntu " + osVer; }
  if (n === "photon") { return "Photon " + major; }
  if (n === "rhel")   { return "Rhel " + major; }
  if (n.indexOf("windows") >= 0) { return "Windows " + osVer; }
  return String(osName) + " " + String(osVer);
}

try {
  var rest = host.createRestClient();

  var nsData = cciGetJson(rest, CCI_NS);
  var nsItems = (nsData && nsData.items) ? nsData.items : [];
  if (nsItems.length === 0) { return ""; }
  var urn = ((nsItems[0].metadata || {}).annotations || {})[URN_ANNOT];
  if (!urn) { return ""; }
  var P = "/proxy/k8s/namespaces/" + urn;

  var libMap = {};
  try {
    var ccl = cciGetJson(rest, P + "/apis/imageregistry.vmware.com/v1alpha2/clustercontentlibraries");
    for each (var lib in (ccl.items || [])) {
      var lid = (lib.metadata || {}).name;
      if (lid) { libMap[String(lid)] = ((lib.status || {}).name) ? String(lib.status.name) : String(lid); }
    }
  } catch (eLib) { System.warn("[getOSSelector] 라이브러리명 매핑 실패(계속): " + eLib); }

  var data = cciGetJson(rest, P + "/apis/run.tanzu.vmware.com/v1alpha3/osimages?limit=500");
  var imgs = (data && data.items) ? data.items : [];

  for each (var img in imgs) {
    var L = (img.metadata || {}).labels || {};
    if (!L["run.tanzu.vmware.com/kubernetesVersion"] || String(L["run.tanzu.vmware.com/kubernetesVersion"]) !== krKey) { continue; }
    var osName = L["os-name"], osVer = L["os-version"], osType = L["os-type"] || "", clId = L["content-library"];
    if (!osName || !clId) { continue; }
    var isWindows = (String(osType).toLowerCase().indexOf("windows") >= 0) || (String(osName).toLowerCase().indexOf("windows") >= 0);
    if (isWindows && !wantWorker) { continue; }

    var libName = libMap[String(clId)] || String(clId);
    var label = osFriendly(osName, osVer) + " - " + libName;
    if (label !== want) { continue; }

    var sel = "os-name=" + osName + ", content-library=" + clId;
    if (String(osName).toLowerCase() === "ubuntu") { sel += ", os-version=" + osVer; }
    System.log("[getOSSelector] '" + want + "' → " + sel);
    return sel;
  }

  System.warn("[getOSSelector] 라벨 매칭 실패 (osImage='" + want + "', kr=" + krKey + ", role=" + (wantWorker?"worker":"controlplane") + ") — '' 반환");
  return "";

} catch (e) {
  System.error("[getOSSelector] 오류 — '' 반환: " + e);
  return "";
}
