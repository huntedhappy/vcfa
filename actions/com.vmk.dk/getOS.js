// Return type: Array/Properties

var OS = [
  { label: "PhotonOS", value: "photon" },
  { label: "UbuntuOS", value: "ubuntu" },
  { label: "WindowsOS", value: "windows" }
];

var results = []; // Array of Properties

for (var i = 0; i < OS.length; i++) {
  var item = OS[i];
  var prop = new Properties();
  prop.put("label", item.label); // 사용자에게 보여질 이름
  prop.put("value", item.value); // 실제 스크립트로 넘어갈 데이터
  results.push(prop);
}

System.log("results.length=" + results.length);
// 로그 확인용 (Properties 객체로 출력됨)
for (var j = 0; j < results.length; j++) {
    System.log("Label: " + results[j].get("label") + ", Value: " + results[j].get("value"));
}

return results;