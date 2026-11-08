Recover middleware should not log panic for aborted handler
### Issue Description

Using proxy and recover middleware would print the panic log in cases where the HTTP client aborts the request.
The error that is recovered is `http.ErrAbortHandler`. That one is a special error to signal aborting the HTTP handler and should not be logged.
From `net/http/server.go` https://github.com/golang/go/blob/88be85f18bf0244a2470fdf6719e1b5ca5a5e50a/src/net/http/server.go#L1775:
```
// ErrAbortHandler is a sentinel panic value to abort a handler.
// While any panic from ServeHTTP aborts the response to the client,
// panicking with ErrAbortHandler also suppresses logging of a stack
// trace to the server's error log.
var ErrAbortHandler = errors.New("net/http: abort Handler")
```
It should be ignored the same way as it is done in `net/http/server.go`.
https://github.com/golang/go/blob/88be85f18bf0244a2470fdf6719e1b5ca5a5e50a/src/net/http/server.go#L1799

See also the comment I found here https://github.com/golang/go/issues/28239#issuecomment-430385295

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs


### Expected behaviour
No stack trace for recovery of the `ErrAbortHandler`

### Actual behaviour
I am seeing log such as:
```
"[PANIC RECOVER] net/http: abort Handler goroutine 45 [running]:
github.com/labstack/echo/v4/middleware.RecoverWithConfig.func1.1.1()
    github.com/labstack/echo/v4@v4.7.1/middleware/recover.go:89 +0x11a
panic({0xa18940, 0xc000112ad0})
    runtime/panic.go:1038 +0x215
net/http/httputil.(*ReverseProxy).ServeHTTP(0xc0004c0140, {0xba8d28, 0xc0005baae0}, 0xc0000ac100)
    net/http/httputil/reverseproxy.go:348 +0xeba
github.com/labstack/echo/v4/middleware.ProxyWithConfig.func1.1({0xbc4260, 0xc0000a8500})
    github.com/labstack/echo/v4@v4.7.1/middleware/proxy.go:260 +0x5f0
...
```

### Steps to reproduce

### Version/commit
github.com/labstack/echo/v4 v4.7.1
