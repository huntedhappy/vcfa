// Inputs: ProjectName (string), NamespaceName (string)  ← 현재는 미사용(라이브러리에서 직접 조회)
// Return type: Array/Properties
// ★ 동적: KR(Kubernetes Release) 버전 = 콘텐츠 라이브러리 아이템 이름에 들어있는 vkr 버전 문자열.
//   이름에 'Kubernetes' 가 들어간 콘텐츠 라이브러리(예: "Kubernetes Service", "Custom Kubernetes Service")의
//   아이템명에서 'vX.Y.Z---vmware.N[-fips]-vkr.M' 패턴을 추출·중복제거.
//     아이템명 예: ob-25157145-ubuntu-2204-amd64-v1.32.10---vmware.1-fips-vkr.2
//   label(name) = 'vX.Y.Z'(짧은 버전, 드롭다운 표시),
//   value(id)   = 전체 'vX.Y.Z---vmware.N[-fips]-vkr.M'(시스템에 전달되는 값).
//   getVMImage.js 와 동일한 VAPIManager → com_vmware_content_library(_item) 패턴(검증된 경로).

var KR_RE = /v\d+\.\d+\.\d+---vmware\.\d+(?:-fips)?-vkr\.\d+/;   // 아이템명에서 KR 버전 추출
var LIB_RE = /kubernetes/i;                                     // 스캔할 라이브러리(이름에 'kubernetes')

var results = [];

var endpoints = VAPIManager.getAllEndpoints();
if (endpoints == null || endpoints.length === 0) {
  System.warn("[getKRVersion] 등록된 vAPI Endpoint 없음 — 빈 목록 반환");
  return [];
}
var vapiEndpoint = endpoints[0];

try {
  var client = vapiEndpoint.client();
  var libraryService = new com_vmware_content_library(client);
  var itemService = new com_vmware_content_library_item(client);

  var libraryIds = libraryService.list();
  var seen = {};

  for each (var libId in libraryIds) {
    var libModel;
    try { libModel = libraryService.get(libId); } catch (eLib) { continue; }
    if (!LIB_RE.test(String(libModel.name))) { continue; }   // KR 이미지 라이브러리만
    System.log("[getKRVersion] scan library=" + libModel.name);

    var itemIds;
    try { itemIds = itemService.list(libId); } catch (eList) { continue; }

    for each (var itemId in itemIds) {
      var nm;
      try { nm = String(itemService.get(itemId).name); } catch (eItem) { continue; }
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
