Latests version crashes on request
# Details

I'm using docker with tag for latest version. Since 1 week when I run container and on first attempt to request metrics containers crashes with:
 sonarr-exporter  | 2023-10-17T13:26:14.970Z     INFO    Starting exportarr      {"app_name": "exportarr", "version": "vmaster", "buildTime": "2023-10-08T18:15:27.347Z", "revision": "b8426af721e5ec7cdeae612686ef9c8083ffc85a"}
sonarr-exporter  | 2023-10-17T13:26:14.971Z     INFO    Starting HTTP Server    {"interface": "0.0.0.0", "port": 9707}
sonarr-exporter  | 2023-10-17T13:26:19.812Z     INFO    Sending HTTP request    {"url": "http://sonarr:8989/api/v3/series"}
sonarr-exporter  | 2023-10-17T13:26:19.812Z     INFO    Sending HTTP request    {"url": "http://sonarr:8989/api/v3/system/status"}
sonarr-exporter  | panic: assignment to entry in nil map
sonarr-exporter  |
sonarr-exporter  | goroutine 35 [running]:
[HIDDEN]
sonarr-exporter  | github.com/prometheus/client_golang/prometheus.(*Registry).Gather.func1()
sonarr-exporter  |      /go/pkg/mod/github.com/prometheus/client_golang@v1.17.0/prometheus/registry.go:455 +0x102
sonarr-exporter  | created by github.com/prometheus/client_golang/prometheus.(*Registry).Gather in goroutine 29
sonarr-exporter  |      /go/pkg/mod/github.com/prometheus/client_golang@v1.17.0/prometheus/registry.go:547 +0xbab


When I'm using v.1.5.5 - everything works OK.

### Additional contract requirements

- Collecting queue metrics must not panic while handling request query parameters; the metrics request should complete normally.
