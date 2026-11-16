Remove the Response argument from ResponseWriter.ServerError until we come up with how to support default error responses
`safehttp.ResponseWriter.ServerError` currently has the following signature:
```go
func (w *ResponseWriter) ServerError(code StatusCode, resp Response) Result
```
It takes a `safehttp.Response` as an argument, but there might be places where we want to respond with a server error without having the ability to create safe responses. For example if a plugin needs to interrupt the handling of an incoming request. We therefore need to reconsider the signature of `ServerError` so that it doesn't take a `Response` or so that it is possible to optionally call without a `Response`.
