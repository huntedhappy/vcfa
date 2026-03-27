var v = String(imageName || "").toLowerCase();
System.log("imageName=" + imageName);
System.log("normalized=" + v);

if (v.indexOf("photon") >= 0) {
    System.log("detected photon");
    return "photon";
}

if (v.indexOf("ubuntu") >= 0) {
    System.log("detected ubuntu");
    return "ubuntu";
}

System.warn("unsupported imageName=" + imageName + ", fallback=ubuntu");
return "ubuntu";