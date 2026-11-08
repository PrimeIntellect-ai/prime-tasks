Consider making host checks in a plugin rather than in the core mux implementation
Currently, host checking is done here: https://github.com/google/go-safeweb/blob/0c930b079f42206df056e531d88cf9009caa6f97/safehttp/mux.go#L173

It might make sense to do it in an interceptor. Especially since we might need to provide convenient ways of configuring the check (e.g. for local development against `localhost`).

### Additional contract requirements

- The core multiplexer must not impose host validation on every request. Host validation remains available as an interceptor that an application can install.
- An application can configure which host names the interceptor accepts, including local-development names such as `localhost`. Requests for configured hosts are allowed through; requests for unconfigured hosts are rejected with 404 Not Found.
- The host check interceptor is provided by the `safehttp/plugins/hostcheck` package. `hostcheck.New(hosts ...string)` returns an interceptor that accepts exactly the listed host names and rejects every other host with 404 Not Found.
