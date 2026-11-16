Expose methods for getting and setting the http.Request context from the safehttp.IncomingRequest
Currently, the `safehttp.IncomingRequest` API doesn't provide methods for retrieving and modifying the `context.Context` of the underlying `http.Request`. Plugins need this functionality to add XSRF tokens and CSP nonces.

### Additional contract requirements

`safehttp.IncomingRequest.Context() context.Context` returns the context associated with its underlying `http.Request`. `safehttp.IncomingRequest.SetContext(ctx context.Context)` replaces the underlying request's context with `ctx`.
