Gzip middleware blocks websockets.
Currently [`gzip` middleware](https://github.com/swaggest/rest/blob/v0.2.36/response/gzip/middleware.go#L26) hides `http.Hijacker` and prevents connection upgrade.

### Additional contract requirements

- The response writer returned by the gzip middleware must implement `http.Hijacker` whenever the original `http.ResponseWriter` does.
- Calling `Hijack` on that writer must perform the hijack on the original writer and return the same `net.Conn`, `*bufio.ReadWriter` and `error` that the original writer's `Hijack` returns.
