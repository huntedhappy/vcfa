// 입력 매개변수(Input parameter): targetLibraryName (타입: string)
// 반환값(Return type): Array/Properties

var results = [];

if (!targetLibraryName || String(targetLibraryName).trim() == "") {
    throw "targetLibraryName 값이 비어 있습니다.";
}

var endpoints = VAPIManager.getAllEndpoints();
if (endpoints == null || endpoints.length === 0) {
    throw "vRO에 등록된 VAPI Endpoint를 찾을 수 없습니다.";
}

var vapiEndpoint = endpoints[0];

try {
    System.log("[getVMImage] targetLibraryName=" + targetLibraryName);

    var client = vapiEndpoint.client();
    var libraryService = new com_vmware_content_library(client);
    var itemService = new com_vmware_content_library_item(client);

    var libraryIds = libraryService.list();
    System.log("[getVMImage] library count=" + libraryIds.length);

    var foundLibrary = false;

    for each (var libId in libraryIds) {
        var libModel = libraryService.get(libId);

        System.log("[getVMImage] checking library name=" + libModel.name + ", id=" + libId);

        if (String(libModel.name).trim() == String(targetLibraryName).trim()) {
            foundLibrary = true;
            System.log("[getVMImage] matched library=" + libModel.name + ", id=" + libId);

            var itemIds = itemService.list(libId);
            System.log("[getVMImage] item count=" + itemIds.length);

            for each (var itemId in itemIds) {
                var itemModel = itemService.get(itemId);

                System.log("[getVMImage] item name=" + itemModel.name + ", id=" + itemId + ", type=" + itemModel.type);

                var prop = new Properties();
                prop.put("label", String(itemModel.name));

                // 1차 테스트는 name
                prop.put("value", String(itemModel.name));

                // 나중에 식별값이 필요하면 아래로 교체
                // prop.put("value", String(itemId));

                results.push(prop);
            }

            break;
        }
    }

    if (!foundLibrary) {
        throw "대상 Content Library를 찾지 못했습니다. targetLibraryName=" + targetLibraryName;
    }

    System.log("[getVMImage] results.length=" + results.length);

    for (var j = 0; j < results.length; j++) {
        System.log("[getVMImage] Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
    }

    return results;

} catch (e) {
    System.error("[getVMImage] 오류 발생: " + e);
    throw e;
}