looping/panic router.go#Find when set param to context
### Issue Description

looping/panic router.go#Find when set param to context

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Expected behaviour
get actual data by request

### Actual behaviour

```
echo: http: panic serving [::1]:54155: runtime error: index out of range [1] with length 1
goroutine 18 [running]:
net/http.(*conn).serve.func1(0xc000096000)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:1801 +0x147
panic(0x1344100, 0xc0000a0020)
	/usr/local/Cellar/go/1.15.2/libexec/src/runtime/panic.go:975 +0x3e9
github.com/labstack/echo/v4.(*Router).Find(0xc00000e940, 0xc0000a0000, 0x3, 0xc0000a0004, 0x12, 0x13d1e60, 0xc0000960a0)
	/Users/andrey/go/pkg/mod/github.com/labstack/echo/v4@v4.1.17/router.go:415 +0x11d2
github.com/labstack/echo/v4.(*Echo).ServeHTTP(0xc00000c1e0, 0x13ce1e0, 0xc0000aa000, 0xc00009e000)
	/Users/andrey/go/pkg/mod/github.com/labstack/echo/v4@v4.1.17/echo.go:619 +0x12b
net/http.serverHandler.ServeHTTP(0xc000178000, 0x13ce1e0, 0xc0000aa000, 0xc00009e000)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:2843 +0xa3
net/http.(*conn).serve(0xc000096000, 0x13ce9a0, 0xc00009a000)
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:1925 +0x8ad
created by net/http.(*Server).Serve
	/usr/local/Cellar/go/1.15.2/libexec/src/net/http/server.go:2969 +0x36c
```

### Steps to reproduce
`curl -X GET -H "Content-Type: application/json" localhost:8811/v1/admin`
panic - `curl -X GET -H "Content-Type: application/json" localhost:8811/v1/view/same-data`
looping - `curl -X GET -H "Content-Type: application/json" localhost:8811/v1/images/view`

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

	v0 := s.Group("/:version")
	v0.GET("/admin", func(c echo.Context) error {
		c.SetParamNames("version")
		c.SetParamValues("v1")
		return nil
	})

	v0.GET("/images/view/:id", handler)
	v0.GET("/images/:id", handler)
	v0.GET("/view/*", func(c echo.Context) error {
		return c.JSON(200, c.Param("*"))
	})

	s.Start(":8811")
}

func handler(c echo.Context) error {
	return c.JSON(200, c.Param("id"))
}
```

### Version/commit
v4.1.17
