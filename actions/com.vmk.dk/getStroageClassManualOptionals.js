// Return type: Array/Properties

var INHERIT_VALUE = "__inherit__";
var STORAGE_POLICIES = [
  { label: "vSAN Default Storage Policy", value: "obcluster-vsan-storage-policy" }
];

var results = [];

// Optional inherit value for fallback behavior.
var inheritProp = new Properties();
inheritProp.put("label", "(상속) OS Disk Storage Class 사용");
inheritProp.put("value", INHERIT_VALUE);
results.push(inheritProp);

for (var i = 0; i < STORAGE_POLICIES.length; i++) {
  var item = STORAGE_POLICIES[i];
  var prop = new Properties();
  prop.put("label", item.label);
  prop.put("value", item.value);
  results.push(prop);
}

System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
  System.log("Label: " + results[j].get("label") + " | Value: " + results[j].get("value"));
}

return results;
