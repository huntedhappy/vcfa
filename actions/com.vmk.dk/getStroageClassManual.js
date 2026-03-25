// Return type: Array/Properties

var STORAGE_POLICIES = [
  { label: "vSAN Default Storage Policy", value: "obcluster-vsan-storage-policy" }
];

var results = [];

for (var i = 0; i < STORAGE_POLICIES.length; i++) {
  var item = STORAGE_POLICIES[i];
  
  // Properties 객체 생성 및 값 할당
  var prop = new Properties();
  prop.put("label", item.label);  // 드롭다운에 표시될 이름
  prop.put("value", item.value);  // 실제 선택 시 전달될 데이터
  
  results.push(prop);
}

// 확인용 로그
System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
    System.log("Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
}

return results;