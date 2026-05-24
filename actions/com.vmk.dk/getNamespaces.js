// Action name 예: getNamespacesNames
// Input: ProjectName (string)
// Return type: Array/string

var hostTypeName = "VCFA:Host";
var hosts = Server.findAllForType(hostTypeName, null);
if (!hosts || hosts.length === 0) {
    throw "No VCFA:Host objects found.";
}
var host = hosts[0];
var cciService = host.cciService;

if (!ProjectName) {
    System.log(">>> ProjectName is empty.");
    return [];
}

System.log(">>> Selected ProjectName = " + ProjectName);

// 2) namespace 조회
var namespaces = cciService.getSupervisorNamespacesForProject(ProjectName);

if (!namespaces || namespaces.length === 0) {
    System.log(">>> No namespaces found for Project: " + ProjectName);
    return [];
}

var nsNames = [];
for (var i = 0; i < namespaces.length; i++) {
    var ns = namespaces[i];
    var nsName = "";
    try { nsName = ns.name; } catch (e) {}
    if (nsName) {
        nsNames.push(nsName.toString());
    }
}

System.log(">>> nsNames = " + nsNames);
return nsNames;