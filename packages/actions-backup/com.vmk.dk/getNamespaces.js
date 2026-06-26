// Action name 예: getNamespacesNames
// Input: ProjectName (string)
// Return type: Array/string
// ★ 이 VCFA 빌드는 Array/string 만 드롭다운 렌더됨. Array/Properties 는 무한로딩(2026-06-26 실측).

var hostTypeName = "VCFA:Host";
var hosts = Server.findAllForType(hostTypeName, null);
if (!hosts || hosts.length === 0) {
    System.warn("No VCFA:Host in Orchestrator inventory — 빈 목록 반환.");
    return [];
}
var host = hosts[0];
var cciService = host.cciService;

if (!ProjectName) {
    System.log(">>> ProjectName is empty.");
    return [];
}

System.log(">>> Selected ProjectName = " + ProjectName);

// 2) namespace 조회 — 실패해도 폼이 안 깨지게 빈 목록 반환
var namespaces;
try {
    namespaces = cciService.getSupervisorNamespacesForProject(ProjectName);
} catch (e) {
    System.warn(">>> namespace 조회 실패 — 빈 목록 반환: " + e);
    return [];
}

if (!namespaces || namespaces.length === 0) {
    System.log(">>> No namespaces found for Project: " + ProjectName);
    return [];
}

var results = [];
for (var i = 0; i < namespaces.length; i++) {
    var ns = namespaces[i];
    var nsName = "";
    try { nsName = ns.name; } catch (e) {}
    if (nsName) {
        results.push(nsName.toString());
    }
}

System.log(">>> namespace results = " + results.length);
return results;
