// Return type: Array/Properties

var INHERIT_VALUE = "__inherit__";
var STORAGE_POLICIES = [
  { label: "vSAN Default Storage Policy", value: "obcluster-vsan-storage-policy" }
];

var results = [];

// Optional inherit value for fallback behavior.
var inheritProp = new Properties();
inheritProp.put("name", "(상속) OS Disk Storage Class 사용");
inheritProp.put("id", INHERIT_VALUE);
results.push(inheritProp);

for (var i = 0; i < STORAGE_POLICIES.length; i++) {
  var item = STORAGE_POLICIES[i];
  var prop = new Properties();
  prop.put("name", item.label);
  prop.put("id", item.value);
  results.push(prop);
}

System.log("results.length=" + results.length);
for (var j = 0; j < results.length; j++) {
  System.log("Label: " + results[j].get("name") + " | Value: " + results[j].get("id"));
}

return results;

