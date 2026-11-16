Unable to add dynamic DC after deleting the last DC from a Seed
### What happened?

After setting up a test cluster with a shared master/seed setup I added one dynamic DC to the seed. After deleting that DC, it is not possible to add a new one. Turns out, the complete `datacenters` key was deleted from the spec of the seed resource. The API crashes with:

```
kubermatic-api-645f8bc66c-mqnl9 api 2022/09/08 16:16:55 http: panic serving 10.136.4.88:47894: assignment to entry in nil map
kubermatic-api-645f8bc66c-mqnl9 api goroutine 3316 [running]:
kubermatic-api-645f8bc66c-mqnl9 api net/http.(*conn).serve.func1()
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:1825 +0xbf
kubermatic-api-645f8bc66c-mqnl9 api panic({0x3174860, 0x406b1d0})
kubermatic-api-645f8bc66c-mqnl9 api 	runtime/panic.go:844 +0x258
kubermatic-api-645f8bc66c-mqnl9 api k8c.io/kubermatic/v2/pkg/handler/v1/dc.CreateEndpoint.func1({0x40957a8, 0xc001981020}, {0x345e020?, 0xc003267b80})
kubermatic-api-645f8bc66c-mqnl9 api 	k8c.io/kubermatic/v2/pkg/handler/v1/dc/datacenter.go:290 +0x59d
kubermatic-api-645f8bc66c-mqnl9 api k8c.io/kubermatic/v2/pkg/handler/middleware.UserSaver.func1.1({0x40957a8, 0xc001980fc0}, {0x345e020, 0xc003267b80})
kubermatic-api-645f8bc66c-mqnl9 api 	k8c.io/kubermatic/v2/pkg/handler/middleware/middleware.go:204 +0x63c
kubermatic-api-645f8bc66c-mqnl9 api k8c.io/kubermatic/v2/pkg/handler/middleware.TokenVerifier.func1.1({0x40957a8, 0xc001980a20}, {0x345e020, 0xc003267b80})
kubermatic-api-645f8bc66c-mqnl9 api 	k8c.io/kubermatic/v2/pkg/handler/middleware/middleware.go:302 +0x765
kubermatic-api-645f8bc66c-mqnl9 api github.com/go-kit/kit/transport/http.Server.ServeHTTP({0xc001c1d890, 0x3b7f068, 0xc001985b30, {0xc001985b80, 0x2, 0x2}, {0x0, 0x0, 0x0}, 0x3b7ee90, ...}, ...)
kubermatic-api-645f8bc66c-mqnl9 api 	github.com/go-kit/kit@v0.12.0/transport/http/server.go:121 +0x35b
kubermatic-api-645f8bc66c-mqnl9 api main.setSecureHeaders.func1({0x7f3d312c8740, 0xc002765ef0}, 0xc0019809f0?)
kubermatic-api-645f8bc66c-mqnl9 api 	k8c.io/kubermatic/v2/cmd/kubermatic-api/main.go:659 +0x305
kubermatic-api-645f8bc66c-mqnl9 api net/http.HandlerFunc.ServeHTTP(0xc003080e00?, {0x7f3d312c8740?, 0xc002765ef0?}, 0x0?)
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:2084 +0x2f
kubermatic-api-645f8bc66c-mqnl9 api github.com/gorilla/mux.(*Router).ServeHTTP(0xc001c76000, {0x7f3d312c8740, 0xc002765ef0}, 0xc003080c00)
kubermatic-api-645f8bc66c-mqnl9 api 	github.com/gorilla/mux@v1.8.0/mux.go:210 +0x1cf
kubermatic-api-645f8bc66c-mqnl9 api github.com/prometheus/client_golang/prometheus/promhttp.InstrumentHandlerCounter.func1({0x4094f50?, 0xc0031970e0?}, 0xc003080c00)
kubermatic-api-645f8bc66c-mqnl9 api 	github.com/prometheus/client_golang@v1.12.2/prometheus/promhttp/instrument_server.go:117 +0xaa
kubermatic-api-645f8bc66c-mqnl9 api net/http.HandlerFunc.ServeHTTP(...)
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:2084
kubermatic-api-645f8bc66c-mqnl9 api main.instrumentHandler.func1({0x4094f50, 0xc0031970e0}, 0xc003080c00)
kubermatic-api-645f8bc66c-mqnl9 api 	k8c.io/kubermatic/v2/cmd/kubermatic-api/metrics.go:65 +0xb0
kubermatic-api-645f8bc66c-mqnl9 api net/http.HandlerFunc.ServeHTTP(0x40939f0?, {0x4094f50?, 0xc0031970e0?}, 0x3b80801?)
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:2084 +0x2f
kubermatic-api-645f8bc66c-mqnl9 api github.com/gorilla/handlers.loggingHandler.ServeHTTP({{0x40752e0, 0xc00000e018}, {0x4077b00, 0xc00270d7e0}, 0xc00272c810}, {0x40939f0, 0xc0018e2380}, 0xc003080c00)
kubermatic-api-645f8bc66c-mqnl9 api 	github.com/gorilla/handlers@v1.5.1/logging.go:47 +0xef
kubermatic-api-645f8bc66c-mqnl9 api net/http.serverHandler.ServeHTTP({0x4083450?}, {0x40939f0, 0xc0018e2380}, 0xc003080c00)
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:2916 +0x43b
kubermatic-api-645f8bc66c-mqnl9 api net/http.(*conn).serve(0xc0018fc000, {0x40957a8, 0xc002732cc0})
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:1966 +0x5d7
kubermatic-api-645f8bc66c-mqnl9 api created by net/http.(*Server).Serve
kubermatic-api-645f8bc66c-mqnl9 api 	net/http/server.go:3071 +0x4db
```
It works again after re-adding  `datacenters: {}` to the seed resource.

### Expected behavior

I can add a new DC to the seed after deleting the last one.

### How to reproduce the issue?

Delete all DCs from a seed and try to add a new one.

### How is your environment configured?

- KKP version: 2.21
- Shared or separate master/seed clusters?: Shared

### Provide your KKP manifest here (if applicable)

The initial seed yaml looks like this:

```yaml
---
apiVersion: kubermatic.k8c.io/v1
kind: Seed
metadata:
  # The Seed *must* be named "kubermatic".
  name: kubermatic
  namespace: kubermatic
spec:
  # these two fields are only informational
  country: AT
  location: City

  # list of datacenters where this seed cluster is allowed to create clusters in
  datacenters: {}

  # reference to the kubeconfig to use when connecting to this seed cluster
  kubeconfig:
    name: kubeconfig-kubermatic
    namespace: kubermatic
```
