panic in op.Authorize when request fails to parse
When `ParseAuthorizeRequest` return an error, `authReq` is `nil`:

https://github.com/zitadel/oidc/blob/de33faa2d89f79e30e19c265d549a0bac4cdb7b9/pkg/op/auth_request.go#L68-L72

[HIDDEN]

https://github.com/zitadel/oidc/blob/de33faa2d89f79e30e19c265d549a0bac4cdb7b9/pkg/op/error.go#L16-L25

I found this while writing test. The code to reproduce is rather complex. I can share the panic output:

<details>

```
Running tool: /usr/bin/go test -timeout 30s -coverprofile=/tmp/vscode-goPackQR/go-code-cover -covermode atomic -run ^TestRoutes$ github.com/zitadel/oidc/v2/pkg/op

--- FAIL: TestRoutes (0.00s)
    --- FAIL: TestRoutes//authorize (0.00s)
panic: runtime error: invalid memory address or nil pointer dereference [recovered]
	panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x38 pc=0x745b20]

goroutine 31 [running]:
testing.tRunner.func1.2({0x84b2a0, 0xbfbcd0})
	/usr/lib/go/src/testing/testing.go:1526 +0x24e
testing.tRunner.func1()
	/usr/lib/go/src/testing/testing.go:1529 +0x39f
panic({0x84b2a0, 0xbfbcd0})
	/usr/lib/go/src/runtime/panic.go:884 +0x213
github.com/zitadel/oidc/v2/pkg/oidc.(*AuthRequest).GetRedirectURI(0x964880?)
	/home/timz/zitadel/oidc/pkg/oidc/authorization.go:91
github.com/zitadel/oidc/v2/pkg/op.AuthRequestError({0x9679b0, 0xc00014e580}, 0xc00007e0a0?, {0x966ed0?, 0x0?}, {0x964880, 0xc0000a4230}, {0x964840, 0xc00007e110})
	/home/timz/zitadel/oidc/pkg/op/error.go:22 +0x135
github.com/zitadel/oidc/v2/pkg/op.Authorize({0x9679b0, 0xc00014e580}, 0xc00050d400, {0x7f00244a21c0?, 0xc00045c000?})
	/home/timz/zitadel/oidc/pkg/op/auth_request.go:70 +0x9cb
github.com/zitadel/oidc/v2/pkg/op.CreateRouter.func2({0x9679b0?, 0xc00014e580?}, 0xbd8001?)
	/home/timz/zitadel/oidc/pkg/op/auth_request.go:55 +0x3c
net/http.HandlerFunc.ServeHTTP(0x967e20?, {0x9679b0?, 0xc00014e580?}, 0xbd80a0?)
	/usr/lib/go/src/net/http/server.go:2122 +0x2f
github.com/zitadel/oidc/v2/pkg/op.(*IssuerInterceptor).setIssuerCtx(0x0?, {0x9679b0, 0xc00014e580}, 0xc00050d300, {0x965880, 0xc000012540})
	/home/timz/zitadel/oidc/pkg/op/context.go:48 +0x1e2
github.com/zitadel/oidc/v2/pkg/op.(*IssuerInterceptor).Handler.func1({0x9679b0?, 0xc00014e580?}, 0xc0000f0e48?)
	/home/timz/zitadel/oidc/pkg/op/context.go:28 +0x4d
net/http.HandlerFunc.ServeHTTP(0xc00045c6c0?, {0x9679b0?, 0xc00014e580?}, 0xc00050d300?)
	/usr/lib/go/src/net/http/server.go:2122 +0x2f
github.com/rs/cors.(*Cors).Handler.func1({0x9679b0, 0xc00014e580}, 0xc00050d300)
	/home/timz/go/pkg/mod/github.com/rs/cors@v1.8.3/cors.go:236 +0x1c4
net/http.HandlerFunc.ServeHTTP(0xc00045c180?, {0x9679b0?, 0xc00014e580?}, 0xc00050d300?)
	/usr/lib/go/src/net/http/server.go:2122 +0x2f
github.com/rs/cors.(*Cors).Handler.func1({0x9679b0, 0xc00014e580}, 0xc00050d300)
	/home/timz/go/pkg/mod/github.com/rs/cors@v1.8.3/cors.go:236 +0x1c4
net/http.HandlerFunc.ServeHTTP(0xc00050d200?, {0x9679b0?, 0xc00014e580?}, 0x750919?)
	/usr/lib/go/src/net/http/server.go:2122 +0x2f
github.com/gorilla/mux.(*Router).ServeHTTP(0xc00045c0c0, {0x9679b0, 0xc00014e580}, 0xc00050d100)
	/home/timz/go/pkg/mod/github.com/gorilla/mux@v1.8.0/mux.go:210 +0x1cf
github.com/zitadel/oidc/v2/pkg/op_test.TestRoutes.func1(0xc000500ea0)
	/home/timz/zitadel/oidc/pkg/op/op_test.go:133 +0x3b0
testing.tRunner(0xc000500ea0, 0xc000090cc0)
	/usr/lib/go/src/testing/testing.go:1576 +0x10b
created by testing.(*T).Run
	/usr/lib/go/src/testing/testing.go:1629 +0x3ea
FAIL	github.com/zitadel/oidc/v2/pkg/op	0.228s
FAIL
```

</details>

### Additional contract requirements

- `Authorize` must handle a failed authorization-request parse without panicking.
