// Return type: Array/Properties
// Inputs: 없음
// ★ 드롭다운은 {label,value} 형식 필요 — Array/string({id,name})이면 UI 가 못 그려 무한로딩.

var hostTypeName = "VCFA:Host";
var hosts = Server.findAllForType(hostTypeName, null);
if (!hosts || hosts.length === 0) {
    // $data 액션은 throw 하면 폼이 깨짐 → 빈 목록 반환. 호스트는 'Add a VCF Automation Host' 워크플로로 등록.
    System.warn("No VCFA:Host in Orchestrator inventory — 빈 목록 반환.");
    return [];
}
var host = hosts[0];

// VCFA Project 전체 조회 — 세션/연결 실패해도 폼이 안 깨지게 빈 목록 반환
var projectTypeName = "VCFA:Project";
var projects;
try {
    projects = Server.findAllForType(projectTypeName, null);
} catch (e) {
    System.warn(">>> VCFA:Project fetchAll 실패 — 빈 목록 반환: " + e);
    return [];
}

if (!projects || projects.length === 0) {
    System.log(">>> VCFA:Project objects not found.");
    return [];
}

System.log(">>> projects.length = " + projects.length);

var results = [];

for (var i = 0; i < projects.length; i++) {
    var p = projects[i];
    var name = "";

    try { name = p.name; } catch (e) {}

    if (name) {
        System.log("Project name = " + name);
        var prop = new Properties();
        prop.put("label", name.toString());
        prop.put("value", name.toString());
        results.push(prop);
    }
}

System.log("projects results = " + results.length);
return results;