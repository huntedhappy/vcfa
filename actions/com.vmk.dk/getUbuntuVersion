// Inputs: os (string)
// Return type: Array/Properties

// [수정] 빈 항목 제거하고 실제 버전만 남김
var UBUNTU_VERSION = [
  { label: "24.04", value: "24.04" },
  { label: "22.04", value: "22.04" }
];

function toLabelValueArray(list) {
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var prop = new Properties();
    prop.put("label", list[i].label);
    prop.put("value", list[i].value);
    out.push(prop);
  }
  return out;
}

var osNorm = (os == null) ? "" : String(os).toLowerCase().trim();

if (osNorm === "ubuntu") {
  return toLabelValueArray(UBUNTU_VERSION);
}

// [유지] Ubuntu가 아닐 때 객체 인식 에러 방지용 (NA)
var dummy = new Properties();
dummy.put("label", "N/A (Not Required)");
dummy.put("value", "NA");

var fallbackResults = [];
fallbackResults.push(dummy);

return fallbackResults;