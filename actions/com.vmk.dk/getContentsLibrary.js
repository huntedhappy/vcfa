// Return type: Array/Properties  <-- [중요] 리턴 타입을 반드시 Array/Properties로 유지하세요.
// ★ 동적: vAPI(Content Library) 에서 라이브러리 목록을 조회 (하드코딩 제거).
//   getVMImage.js 와 동일한 VAPIManager → com_vmware_content_library 패턴(검증된 경로).
//   name = 라이브러리 이름(드롭다운 표시), id = 라이브러리 id(cl-…, 폼에 전달되는 값).
//   엔드포인트/조회 실패 시 폼이 안 깨지게 빈 목록 반환.

var results = [];

var endpoints = VAPIManager.getAllEndpoints();
if (endpoints == null || endpoints.length === 0) {
  System.warn("[getContentsLibrary] 등록된 vAPI Endpoint 없음 — 빈 목록 반환");
  return [];
}
var vapiEndpoint = endpoints[0];

try {
  var client = vapiEndpoint.client();
  var libraryService = new com_vmware_content_library(client);

  var libraryIds = libraryService.list();
  System.log("[getContentsLibrary] library count=" + libraryIds.length);

  var seen = {};
  for each (var libId in libraryIds) {
    var libModel = libraryService.get(libId);
    var name = String(libModel.name);
    var id = String(libModel.id || libId);
    if (!id || seen[id]) { continue; }
    seen[id] = true;

    var prop = new Properties();
    prop.put("name", name);   // UI 에 보일 이름 (예: kr-subs)
    prop.put("id", id);       // 폼에 전달될 라이브러리 id (예: cl-3d26…)
    results.push(prop);

    System.log("[getContentsLibrary] Label: " + name + " | Value: " + id);
  }

  System.log("[getContentsLibrary] results.length=" + results.length);
  return results;

} catch (e) {
  System.error("[getContentsLibrary] 오류 발생 — 빈 목록 반환: " + e);
  return results;
}
