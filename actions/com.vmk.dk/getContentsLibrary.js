// Return type: Array/Properties  <-- [중요] 리턴 타입을 반드시 Array/Properties로 변경하세요.

var CL = [
  { label: "kr-subs", value: "cl-3d26d6e2a9bf8ba6e" },
  { label: "custom-kr", value: "cl-3c6c95a0c70a015d8" }
];

var results = [];

for (var i = 0; i < CL.length; i++) {
  var item = CL[i];
  
  // Properties 객체 생성 및 값 매핑
  var prop = new Properties();
  prop.put("label", item.label);  // 화면에 보일 이름 (예: kr-subs)
  prop.put("value", item.value);  // 실제 ID 값 (예: cl-3d26...)
  
  results.push(prop);
}

// 확인용 로그
System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
    System.log("Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
}

return results;