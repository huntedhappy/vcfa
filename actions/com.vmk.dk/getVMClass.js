// Return type: Array/Properties

var VMCLASS = [
  { label: "2C 4G", value: "best-effort-small" },
  { label: "4C 32G", value: "best-effort-xlarge" },
  { label: "2C 2G", value: "best-effort-xsmall" },
  { label: "4C 8G", value: "custom-best-effort-large-4c-8g" },
  { label: "8C 16G", value: "custom-best-effort-xlarge-8c-16g" }
];

var results = [];

for (var i = 0; i < VMCLASS.length; i++) {
  var item = VMCLASS[i];
  
  // Properties 객체 생성 및 값 매핑
  var prop = new Properties();
  prop.put("label", item.label);  // 화면에 보일 이름 (예: 2C 4G)
  prop.put("value", item.value);  // 실제 값 (예: best-effort-small)
  
  results.push(prop);
}

// 확인용 로그
System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
    System.log("Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
}

return results;