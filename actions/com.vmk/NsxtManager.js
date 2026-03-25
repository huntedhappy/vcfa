return {
    _config: function () {
        if (manager === undefined || manager == null || manager == "") {
            manager = "Default";
        }
        var data = System.getModule("com.vmk").ConfManager().load("VMK/NsxtManager/" + manager);
        return {
            baseUrl: data.url,
            headers: {
                "Authorization": data.auth,
                "Content-Type": "application/json",
                "Accept": "application/json"
            }
        }
    } (),
    _curl: System.getModule("com.vmk.tool").cURL(),
    get: function (url) { return JSON.parse(this._curl.get(this._config.baseUrl + url, this._config.headers)); },
    post: function (url, data) { return JSON.parse(this._curl.post(this._config.baseUrl + url, JSON.stringify(data), this._config.headers)); },
    put: function (url, data) { return JSON.parse(this._curl.put(this._config.baseUrl + url, JSON.stringify(data), this._config.headers)); },
    patch: function (url, data) { return JSON.parse(this._curl.patch(this._config.baseUrl + url, JSON.stringify(data), this._config.headers)); },
    delete: function (url) { return JSON.parse(this._curl.delete(this._config.baseUrl + url, this._config.headers)); }
}