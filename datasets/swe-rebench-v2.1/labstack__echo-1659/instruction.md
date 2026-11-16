HTTP panic when using static and params routers
### Issue Description

HTTP panic when using static and params routers

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Expected behaviour

router not found

### Actual behaviour
```
echo: http: panic serving [::1]:60088: runtime error: index out of range [-1]
goroutine 6 [running]:
net/http.(*conn).serve.func1(0xc0001337c0)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:1801 +0x147
panic(0x1343e40, 0xc000016580)
	/usr/local/Cellar/go/1.15.2/libexec/src/runtime/panic.go:975 +0x3e9
github.com/labstack/echo/v4.(*Router).Find(0xc00000e940, 0xc000016560, 0x3, 0xc000016564, 0x12, 0x13d1b80, 0xc000133860)
	/Users/andrey/go/pkg/mod/github.com/labstack/echo/v4@v4.1.17/router.go:431 +0x11ca
github.com/labstack/echo/v4.(*Echo).ServeHTTP(0xc00000c1e0, 0x13cdf00, 0xc0001781c0, 0xc000184000)
	/Users/andrey/go/pkg/mod/github.com/labstack/echo/v4@v4.1.17/echo.go:619 +0x12b
net/http.serverHandler.ServeHTTP(0xc000178000, 0x13cdf00, 0xc0001781c0, 0xc000184000)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:2843 +0xa3
net/http.(*conn).serve(0xc0001337c0, 0x13ce6c0, 0xc0000786c0)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:1925 +0x8ad
created by net/http.(*Server).Serve
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:2969 +0x36c
```
### Steps to reproduce

`curl -X GET -H "Content-Type: application/json"  localhost:8811/users/creates`

### Working code to debug

```go
package main

import (
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

func main() {
	s := echo.New()
	s.Use(middleware.Logger())
	users := s.Group("/users")

	users.GET("/create", func(c echo.Context) error {
		return nil
	})
	users.GET("/:id/edit", func(c echo.Context) error {
		return nil
	})
	users.GET("/:id/active", func(c echo.Context) error {
		return nil
	})

	s.Start(":8811")
}
```

### Version/commit
v4.1.17
