http-endpoint and metrics server seem not to be working in snapshot-controller
Hi,
I just tried to enable the http-endpoint on the `snapshot-controller:v4.1.1` deployment as described [in the docs](https://github.com/kubernetes-csi/external-snapshotter/tree/v4.1.1#snapshot-controller-command-line-options). The resulting manifest currently looks like this:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snapshot-controller
  namespace: kube-system
spec:
  minReadySeconds: 15
  replicas: 2
  selector:
    matchLabels:
      app: snapshot-controller
  strategy:
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: snapshot-controller
    spec:
      containers:
      - args:
        - --v=5
        - --leader-election=true
        - --http-endpoint=:8080
        - --metrics-path=/metrics
        image: k8s.gcr.io/sig-storage/snapshot-controller:v4.1.1
        imagePullPolicy: IfNotPresent
        name: snapshot-controller
        ports:
        - containerPort: 8080
          name: http
      serviceAccount: snapshot-controller
```

The logs indicate that the server was started:

```
I0806 07:32:03.910275       1 main.go:113] Version: v4.1.1
I0806 07:32:03.911956       1 main.go:156] Metrics server successfully started on :8080, /metrics
I0806 07:32:03.912124       1 main.go:162] Start NewCSISnapshotController with kubeconfig [] resyncPeriod [15m0s]
```

But when i port-forward port `8080` I get the following responses:

```console
❯ curl -v localhost:8080/metrics
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8080 (#0)
> GET /metrics HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/7.68.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: text/plain; version=0.0.4; charset=utf-8
< Date: Fri, 06 Aug 2021 07:33:26 GMT
< Content-Length: 0
<
* Connection #0 to host localhost left intact
```
```console
❯ curl -v localhost:8080/healthz/leader-election
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8080 (#0)
> GET /healthz/leader-election HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/7.68.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 404 Not Found
< Content-Type: text/plain; charset=utf-8
< X-Content-Type-Options: nosniff
< Date: Fri, 06 Aug 2021 07:34:19 GMT
< Content-Length: 19
<
404 page not found
* Connection #0 to host localhost left intact
```

Is there anythin I'm missing in my setup?

### Additional contract requirements

- `MetricsManager` must provide `PrepareMetricsPath(mux *http.ServeMux, pattern string, logger promhttp.Logger) error`. Calling it registers the manager's Prometheus metrics handler on the supplied mux at the supplied pattern and does not start an HTTP server; the caller controls server lifecycle.
- When the snapshot-controller is started with `--http-endpoint` and `--metrics-path`, the configured HTTP endpoint serves Prometheus metrics at that path.
- When leader election is enabled together with the configured HTTP endpoint, `GET /healthz/leader-election` is available on that endpoint and does not return 404.
