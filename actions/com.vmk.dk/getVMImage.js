// 입력 매개변수(Input parameter): os (string) — "ubuntu" | "photon" (폼의 OS 드롭다운에서 전달)
// Return type: Array/Properties
// ★ 동적: 배포 가능한 VM 이미지 = Supervisor 의 ClusterVirtualMachineImage 중 *선택한 OS* 것만.
//   (= 블루프린트 VirtualMachine.spec.imageName 이 실제로 받는 값. vCenter Content Library 아이템 아님).
//   ★ 이 템플릿의 cloud-init 은 ubuntu(apt)/photon(tdnf) 만 지원 → rhel/windows 는 항상 제외("사용 가능한 것만").
//   흐름 (getContentsLibrary/getKRVersion 와 동일한 vRO host.createRestClient → CCI/proxy 직접 GET — 검증된 패턴):
//     1) CCI supervisornamespaces → 첫 namespace 의 URN
//        (metadata.annotations["infrastructure.cci.vmware.com/id"], 예: urn:vcloud:namespace:...)
//     2) /proxy/k8s/namespaces/<URN>/apis/vmoperator.vmware.com/v1alpha3/clustervirtualmachineimages
//   필터: status.osInfo.type(권위) 또는 status.name 에 OS 키워드 매치.
//   name(label)=value(id)=status.name (친근 display name, 예: ob-...-ubuntu-2404-amd64-v1.35.0---vmware.2-vkr.4).
//   ★ status.name 을 값으로: imageName 의 display-name resolver 웹훅이 단일 이미지로 풀어주고(CRD 상 vmi-명/display name 둘 다 허용),
//     폼의 'contains: ubuntu/photon' 가시성·getAdminUserByImage OS 추론이 이름 문자열에 의존하므로.
//   os 미지정/알수없음 → 지원 OS(ubuntu+photon) 전체 반환(여전히 rhel/windows 제외). 실패 시 폼이 안 깨지게 빈 목록.

var CCI_NS = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=1";
var URN_ANNOT = "infrastructure.cci.vmware.com/id";
var CVMI_VERSIONS = ["v1alpha3", "v1alpha2"];   // 블루프린트 VM 과 동일 우선, 미지원 환경 대비 폴백

var want = String(os || "").toLowerCase();   // "ubuntu" | "photon" | ""

function imgOsTokens(img) {
  var st = img.status || {};
  var oi = st.osInfo || {};
  var t = oi.type ? String(oi.type).toLowerCase() : "";
  var nm = st.name ? String(st.name).toLowerCase() : "";
  return { isUbuntu: (t.indexOf("ubuntu") >= 0 || nm.indexOf("ubuntu") >= 0),
           isPhoton: (t.indexOf("photon") >= 0 || nm.indexOf("photon") >= 0) };
}

function matchesOs(img) {
  var k = imgOsTokens(img);
  if (want === "ubuntu") { return k.isUbuntu; }
  if (want === "photon") { return k.isPhoton; }
  return k.isUbuntu || k.isPhoton;   // os 미지정 → 지원 OS 전체(rhel/windows 제외)
}

var results = [];

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) {
  System.warn("[getVMImage] VCFA:Host 없음 — 빈 목록 반환");
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
    System.warn("[getVMImage] supervisornamespace 없음 — 빈 목록 반환");
    return [];
  }
  var meta = nsItems[0].metadata || {};
  var annot = meta.annotations || {};
  var urn = annot[URN_ANNOT];
  if (!urn) {
    System.warn("[getVMImage] namespace URN(annotation " + URN_ANNOT + ") 없음 — 빈 목록 반환");
    return [];
  }

  // 2) ClusterVirtualMachineImage 조회 (v1alpha3 우선, 실패 시 v1alpha2)
  var data = null;
  for each (var ver in CVMI_VERSIONS) {
    var path = "/proxy/k8s/namespaces/" + urn +
               "/apis/vmoperator.vmware.com/" + ver + "/clustervirtualmachineimages";
    try {
      data = cciGetJson(rest, path);
      System.log("[getVMImage] " + ver + " OK (os filter=" + (want || "(all supported)") + ")");
      break;
    } catch (eVer) {
      System.warn("[getVMImage] " + ver + " 실패: " + eVer);
      data = null;
    }
  }
  if (!data) {
    System.warn("[getVMImage] clustervirtualmachineimages 조회 실패(모든 버전) — 빈 목록 반환");
    return [];
  }

  var imgs = (data && data.items) ? data.items : [];
  var seen = {};

  for each (var img in imgs) {
    if (!matchesOs(img)) { continue; }         // 지원 OS + 선택 OS 필터(rhel/windows 제외)
    var istatus = img.status || {};
    var name = istatus.name ? String(istatus.name) : "";   // 친근한 display name
    if (!name || seen[name]) { continue; }
    seen[name] = true;

    var prop = new Properties();
    prop.put("name", name);   // UI 표시 = 이미지 display name
    prop.put("id", name);     // 전달 값 = 동일 display name (imageName 웹훅이 resolve)
    results.push(prop);
  }

  results.sort(function (a, b) {
    var an = String(a.get("name")), bn = String(b.get("name"));
    return (an < bn) ? -1 : (an > bn ? 1 : 0);
  });

  System.log("[getVMImage] os=" + (want || "(all)") + " → results.length=" + results.length);
  for (var j = 0; j < results.length; j++) {
    System.log("[getVMImage] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
  }
  return results;

} catch (e) {
  System.error("[getVMImage] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
