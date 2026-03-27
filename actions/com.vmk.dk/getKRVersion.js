// Return type: Array/Properties

var KR_VERSION = [
  { label: "v1.32.10", value: "v1.32.10---vmware.1-fips-vkr.2" },
  { label: "v1.33.1", value: "v1.33.1---vmware.1-fips-vkr.2" },
  { label: "v1.33.3", value: "v1.33.3---vmware.1-fips-vkr.1" },
  { label: "v1.33.6", value: "v1.33.6---vmware.1-fips-vkr.2" },
  { label: "v1.34.1", value: "v1.34.1---vmware.1-vkr.4" },
  { label: "v1.34.2", value: "v1.34.2---vmware.2-vkr.2" },
  { label: "v1.34.1", value: "v1.34.1---vmware.1-vkr.4" }
];

var results = [];

for (var i = 0; i < KR_VERSION.length; i++) {
  var item = KR_VERSION[i];
  
  // Properties 객체 생성 및 값 매핑
  var prop = new Properties();
  prop.put("label", item.label);  // 화면에 보이는 짧은 버전 이름
  prop.put("value", item.value);  // 실제 시스템에 전달될 전체 버전 문자열
  
  results.push(prop);
}

// 확인용 로그
System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
    System.log("Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
}

return results;