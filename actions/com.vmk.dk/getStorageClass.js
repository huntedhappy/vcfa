// Return type: Array/Properties

var results = [];
function toStorageClassValue(name) {
    var normalized = ("" + name).toLowerCase();
    normalized = normalized.replace(/[^a-z0-9]+/g, "-");
    normalized = normalized.replace(/^-+/, "").replace(/-+$/, "");
    if (!normalized) {
        normalized = "sc";
    }
    return normalized;
}

// 1. [수정 및 추가된 부분] 하드코딩된 배열을 삭제하고 vCenter의 스토리지 정책을 동적으로 조회합니다.
var vcenters = VcPlugin.allSdkConnections;

for (var i = 0; i < vcenters.length; i++) {
    var vc = vcenters[i];
    try {
        var pbmProfileManager = vc.storageManagement.pbmProfileManager;
        
        var resourceType = new PbmProfileResourceType();
        resourceType.resourceType = "STORAGE";
        
        // vCenter의 SPBM(Storage Policy Based Management) 프로파일 ID 조회
        var profileIds = pbmProfileManager.pbmQueryProfile(resourceType, null);
        
        if (profileIds && profileIds.length > 0) {
            // 프로파일 ID를 기반으로 실제 데이터(이름 등) 추출
            var profiles = pbmProfileManager.pbmRetrieveContent(profileIds);
            
            for (var k = 0; k < profiles.length; k++) {
                var profile = profiles[k];
                var prop = new Properties();
                
                // 2. [수정된 부분] label은 원본 이름, value는 Kubernetes storageClassName 규칙에 맞게 정규화합니다.
                prop.put("label", profile.name); 
                prop.put("value", toStorageClassValue(profile.name));
                
                results.push(prop);
            }
        }
    } catch (e) {
        System.warn("Failed to retrieve storage policies from " + vc.name + ": " + e);
    }
}

// 3. [추가된 부분] 'k8s'와 같이 드롭다운에 항상 노출되어야 하는 정적 값이 있다면 수동으로 추가합니다.
var k8sProp = new Properties();
k8sProp.put("label", "k8s");
k8sProp.put("value", "k8s");
results.push(k8sProp);

// 4. [추가된 부분] 다중 vCenter 환경에서 동일한 이름의 스토리지 정책이 중복 노출되는 것을 방지합니다.
var uniqueResults = [];
var seen = {};
for (var m = 0; m < results.length; m++) {
    var value = results[m].get("value");
    if (!seen[value]) {
        seen[value] = true;
        uniqueResults.push(results[m]);
    }
}

// 5. [수정된 부분] 확인용 로그 대상과 최종 반환(return) 대상을 uniqueResults로 변경했습니다.
System.log("uniqueResults.length=" + uniqueResults.length);
for (var j = 0; j < uniqueResults.length; j++) {
    System.log("Label: " + uniqueResults[j].get("label") + " | Value: " + uniqueResults[j].get("value"));
}

return uniqueResults;
