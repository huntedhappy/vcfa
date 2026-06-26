// ── 진단(read-only) — getVMClass / getStroageClassManual 의 동적 소스 찾기용 ──
// Input: ProjectName (string)   ← 알려진 프로젝트명 하나
// Return type: Array/string
// 라이브 vRO 에서 RUN → 로그(또는 반환 배열)를 그대로 붙여주면, 그 메서드/속성 이름으로
// vmClasses·storageClasses 동적 조회 액션을 추측 없이 구현합니다.
// 안전: 아무것도 변경하지 않음(메서드 이름·속성 값만 읽어서 로그).

var out = [];
function log(s) { System.log(s); out.push(String(s)); }

// Java 객체의 실제 메서드 이름을 리플렉션으로 신뢰성 있게 열거 (for-in 은 Java 메서드를 놓칠 수 있음)
function methodsOf(obj, label) {
  try {
    var ms = obj.getClass().getMethods();
    var seen = {}, keys = [];
    for (var i = 0; i < ms.length; i++) {
      var n = ms[i].getName();
      if (!seen[n]) { seen[n] = true; keys.push(n); }
    }
    keys.sort();
    log(label + " (" + obj.getClass().getName() + ") methods: " + keys.join(", "));
  } catch (e) {
    log(label + " methods 조회 실패: " + e);
  }
}

var hosts = Server.findAllForType("VCFA:Host", null);
if (!hosts || hosts.length === 0) { log("VCFA:Host 없음 — 호스트 등록 먼저"); return out; }
var host = hosts[0];
methodsOf(host, "host");

var cci = null;
try { cci = host.cciService; methodsOf(cci, "cciService"); }
catch (e) { log("host.cciService 접근 실패: " + e); }

if (cci) {
  try {
    var nss = cci.getSupervisorNamespacesForProject(ProjectName);
    log("namespaces count=" + (nss ? nss.length : "null") + " (project=" + ProjectName + ")");
    if (nss && nss.length > 0) {
      var ns = nss[0];
      methodsOf(ns, "namespace[0]");
      // 흔한 후보 속성 직접 접근 시도 (있으면 값, 없으면 사유 로그)
      var probes = ["name", "storageClasses", "vmClasses", "status", "spec", "classConfigOverrides"];
      for (var p = 0; p < probes.length; p++) {
        try { log("ns." + probes[p] + " = " + String(ns[probes[p]])); }
        catch (e2) { log("ns." + probes[p] + " 접근불가: " + e2); }
      }
    }
  } catch (e3) {
    log("getSupervisorNamespacesForProject 실패: " + e3);
  }
}

// REST 클라이언트 표면 — getVMClass/getStorageClassManual 을 위해 CCI GET 방법 찾기
try {
  var rc = host.createRestClient();
  methodsOf(rc, "restClient");
  try { log("host.getApiToken() length=" + String(host.getApiToken()).length); } catch (e9) { log("getApiToken 실패: " + e9); }
} catch (e8) {
  log("createRestClient 실패: " + e8);
}

// 실제 CCI GET 시도 — 응답 객체 표면 + 내용 확인
try {
  var rest2 = host.createRestClient();
  var path = "/cci/kubernetes/apis/infrastructure.cci.vmware.com/v1alpha3/supervisornamespaces?limit=2";
  var request = rest2.createRequest("GET", path, null);
  methodsOf(request, "request");
  var resp = rest2.execute(request);
  methodsOf(resp, "response");
  var getters = ["getContentAsString", "getStatusCode"];
  for (var g = 0; g < getters.length; g++) {
    try { log("resp." + getters[g] + "() = " + String(resp[getters[g]]()).substring(0, 400)); }
    catch (eg) { log("resp." + getters[g] + "() 실패: " + eg); }
  }
} catch (eGet) {
  log("rest.get 실패: " + eGet);
}

log("=== dumpCciSurface 끝 (" + out.length + " 줄) ===");
return out;
