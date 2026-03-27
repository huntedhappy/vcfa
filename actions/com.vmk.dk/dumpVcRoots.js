var vcs = Server.findAllForType("VC:SdkConnection");

System.log("VC:SdkConnection count = " + (vcs ? vcs.length : "null"));

if (!vcs || vcs.length === 0) {
  throw "VC:SdkConnection 없음";
}

var out = [];
for (var i = 0; i < vcs.length; i++) {
  var line = "name=" + vcs[i].name + " | id=" + vcs[i].id + " | toString=" + String(vcs[i]);
  System.log(line);
  out.push(line);
}

return out;
