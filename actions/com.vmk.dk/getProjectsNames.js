// Return type: Array/string
// Inputs: 없음

var hostTypeName = "VCFA:Host";
var hosts = Server.findAllForType(hostTypeName, null);
if (!hosts || hosts.length === 0) {
    throw "No VCFA:Host objects found.";
}
var host = hosts[0];

// VCFA Project 전체 조회
var projectTypeName = "VCFA:Project";
var projects = Server.findAllForType(projectTypeName, null);

if (!projects || projects.length === 0) {
    System.log(">>> VCFA:Project objects not found.");
    return [];
}

System.log(">>> projects.length = " + projects.length);

var projectNames = [];

for (var i = 0; i < projects.length; i++) {
    var p = projects[i];
    var name = "";

    try { name = p.name; } catch (e) {}

    if (name) {
        System.log("Project name = " + name);
        projectNames.push(name.toString());
    }
}

System.log("projectNames = " + projectNames);
return projectNames;