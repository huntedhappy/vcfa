// Return type: Array/Properties
// ★ 수동(manual) 변형: KR(Kubernetes Release) 버전을 *손으로 관리*하는 정적 목록.
//   동적 버전 getKRVersion 은 CCI clustervirtualmachineimages 에서 자동 추출하지만,
//   이 액션은 아래 KR 배열을 직접 편집해서 노출할 버전을 고정/제한할 때 사용 (getOS.js 와 동일한 정적 패턴).
//   출력 형식은 동적 getKRVersion 과 동일: label(name)='vX.Y.Z'(짧은 표시),
//   value(id)='vX.Y.Z---vmware.N[-fips]-vkr.M'(시스템 전달 전체값).
//   ※ 버전 추가/삭제/순서변경은 아래 KR 배열만 수정하면 됩니다.
//   ※ 입력 없음 — 폼이 ProjectName/NamespaceName 을 넘겨도 무시(미선언 파라미터).

var KR = [
  { label: "v1.32.10", value: "v1.32.10---vmware.1-fips-vkr.2" },
  { label: "v1.33.1",  value: "v1.33.1---vmware.1-fips-vkr.2" },
  { label: "v1.33.3",  value: "v1.33.3---vmware.1-fips-vkr.1" },
  { label: "v1.33.6",  value: "v1.33.6---vmware.1-fips-vkr.2" },
  { label: "v1.34.1",  value: "v1.34.1---vmware.1-vkr.4" },
  { label: "v1.34.2",  value: "v1.34.2---vmware.2-vkr.2" },
  { label: "v1.35.0",  value: "v1.35.0---vmware.2-vkr.4" },
  { label: "v1.35.2",  value: "v1.35.2---vmware.1-vkr.3" }
];

var results = [];

for (var i = 0; i < KR.length; i++) {
  var item = KR[i];
  if (!item || !item.value) { continue; }
  var prop = new Properties();
  prop.put("name", String(item.label || item.value));   // UI 표시
  prop.put("id", String(item.value));                    // 전달 값
  results.push(prop);
}

System.log("[getKRVersionManual] results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
  System.log("[getKRVersionManual] Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
}

return results;
