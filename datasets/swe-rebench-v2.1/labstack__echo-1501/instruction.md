Function looping router.go#Find
### Issue Description

Example code has the one registered route

```golang
e := echo.New()
// Routes
e.GET("/assets/:id", assetID)
...
// assetID mock of the real handler
func assetID(c echo.Context) error {
	return c.String(http.StatusOK, "assetID")
}
```

when request uri is `/assets/tree/free` application is looping...

if application is simple then another requests are processing, but in complex application it's don't answer to any requests and need `kill -9 pid`
current request deadlocking...
### Checklist

- [ x] Dependencies installed
- [ x] No typos
- [ x] Searched existing issues and docs
very similar issue#1461

### Expected behaviour

`404 {"message":"Not Found"}`

### Actual behaviour

```bash
curl  http://localhost:1323/assets/3/e
{"message":"Not Found"}

curl  http://localhost:1323/assets/tree/free
# looping and stop answer...
```

### Steps to reproduce

- run code below
- make curl request `curl  http://localhost:1323/assets/tree/free`

### Working code to debug

```go
package main

import (
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"net/http"
)

func main() {
	// Echo instance
	e := echo.New()

	// Middleware
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	// Routes
	e.GET("/assets/:id", assetID)
	// Start server
	e.Logger.Fatal(e.Start(":1323"))
}

// assetID mock of the real handler
func assetID(c echo.Context) error {
	return c.String(http.StatusOK, "assetID")
}
```

### Version/commit

**4.1.14**
