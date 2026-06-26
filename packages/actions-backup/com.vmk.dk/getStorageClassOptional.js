// Return type: Array/Properties

var results = [];
var INHERIT_VALUE = "__inherit__";
var INHERIT_LABEL = "(상속) OS Disk Storage Class 사용";
var K8S_VALUE = "k8s";
function toStorageClassValue(name) {
    var normalized = ("" + name).toLowerCase();
    normalized = normalized.replace(/[^a-z0-9]+/g, "-");
    normalized = normalized.replace(/^-+/, "").replace(/-+$/, "");
    if (!normalized) {
        normalized = "sc";
    }
    return normalized;
}

var inheritProp = new Properties();
inheritProp.put("name", INHERIT_LABEL);
inheritProp.put("id", INHERIT_VALUE);
results.push(inheritProp);

var k8sProp = new Properties();
k8sProp.put("name", K8S_VALUE);
k8sProp.put("id", K8S_VALUE);
results.push(k8sProp);

try {
    var vcenters = VcPlugin.allSdkConnections || [];

    for (var i = 0; i < vcenters.length; i++) {
        var vc = vcenters[i];
        try {
            var pbmProfileManager = vc.storageManagement.pbmProfileManager;

            var resourceType = new PbmProfileResourceType();
            resourceType.resourceType = "STORAGE";

            var profileIds = pbmProfileManager.pbmQueryProfile(resourceType, null);

            if (profileIds && profileIds.length > 0) {
                var profiles = pbmProfileManager.pbmRetrieveContent(profileIds);

                for (var k = 0; k < profiles.length; k++) {
                    var profile = profiles[k];
                    var prop = new Properties();
                    prop.put("name", profile.name);
                    prop.put("id", toStorageClassValue(profile.name));
                    results.push(prop);
                }
            }
        } catch (e) {
            System.warn("Failed to retrieve storage policies from " + vc.name + ": " + e);
        }
    }
} catch (eTop) {
    System.warn("Failed to access vCenter SDK connections: " + eTop);
}

try {
    var uniqueResults = [];
    var seen = {};
    for (var m = 0; m < results.length; m++) {
        var value = "" + results[m].get("id");
        if (!seen[value]) {
            seen[value] = true;
            uniqueResults.push(results[m]);
        }
    }

    if (!uniqueResults || uniqueResults.length === 0) {
        System.warn("getStorageClassOptional uniqueResults is empty. returning fallback values.");
        var fallbackInherit = new Properties();
        fallbackInherit.put("name", INHERIT_LABEL);
        fallbackInherit.put("id", INHERIT_VALUE);
        var fallbackK8s = new Properties();
        fallbackK8s.put("name", K8S_VALUE);
        fallbackK8s.put("id", K8S_VALUE);
        return [fallbackInherit, fallbackK8s];
    }

    System.log("getStorageClassOptional uniqueResults.length=" + uniqueResults.length);
    for (var j = 0; j < uniqueResults.length; j++) {
        System.log("Label: " + uniqueResults[j].get("name") + " | Value: " + uniqueResults[j].get("id"));
    }

    return uniqueResults;
} catch (eDedup) {
    System.error("getStorageClassOptional failed while finalizing results: " + eDedup);
    var errInherit = new Properties();
    errInherit.put("name", INHERIT_LABEL);
    errInherit.put("id", INHERIT_VALUE);
    var errK8s = new Properties();
    errK8s.put("name", K8S_VALUE);
    errK8s.put("id", K8S_VALUE);
    return [errInherit, errK8s];
}

