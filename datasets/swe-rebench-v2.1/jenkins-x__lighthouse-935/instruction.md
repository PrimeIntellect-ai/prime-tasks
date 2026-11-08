Panic in util.ExternalPluginsForEvent when there is no agent configuration
```
2020/08/18 13:17:24 http: panic serving [::1]:63875: runtime error: invalid memory address or nil pointer dereference
goroutine 100 [running]:
net/http.(*conn).serve.func1(0xc0000db0e0)
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:1795 +0x139
panic(0x22c6300, 0x3399f90)
        /Users/hardy/.gvm/gos/go1.13.15/src/runtime/panic.go:679 +0x1b2
github.com/jenkins-x/lighthouse/pkg/util.ExternalPluginsForEvent(0xc0001fb790, 0x24d36bb, 0x4, 0xc0004e5f40, 0x1a, 0xc0004fb970, 0xf, 0xc0004e5f40)
        /Users/hardy/work/go/src/github.com/jenkins-x/lighthouse/pkg/util/externalplugins.go:262 +0xb4
github.com/jenkins-x/lighthouse/pkg/webhook.(*Options).handleWebHookRequests(0xc0000f0420, 0x27687c0, 0xc0004c01c0, 0xc000474200)
        /Users/hardy/work/go/src/github.com/jenkins-x/lighthouse/pkg/webhook/webhook.go:251 +0x94a
net/http.HandlerFunc.ServeHTTP(0xc000407180, 0x27687c0, 0xc0004c01c0, 0xc000474200)
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:2036 +0x44
net/http.(*ServeMux).ServeHTTP(0xc0000ec6c0, 0x27687c0, 0xc0004c01c0, 0xc000474200)
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:2416 +0x1bd
net/http.serverHandler.ServeHTTP(0xc0004c00e0, 0x27687c0, 0xc0004c01c0, 0xc000474200)
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:2831 +0xa4
net/http.(*conn).serve(0xc0000db0e0, 0x276ea80, 0xc0000eda40)
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:1919 +0x875
created by net/http.(*Server).Serve
        /Users/hardy/.gvm/gos/go1.13.15/src/net/http/server.go:2957 +0x384
```
