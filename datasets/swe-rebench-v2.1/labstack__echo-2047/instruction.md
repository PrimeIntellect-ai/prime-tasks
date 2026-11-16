Escaping colon does not work
### Issue Description

The PR from https://github.com/labstack/echo/pull/1988 doesn't seem to work.

### Expected behaviour

should match routes

### Actual behaviour

none of the routes are matched

### Steps to reproduce

Code below

### Working code to debug

```go
package main

import (
	"github.com/imroc/req"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"net/http"
	"testing"
	"time"
)

func TestEscape(t *testing.T) {
	e := echo.New()
	e.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			t.Logf("%s %s", c.Request().Method, c.Request().URL.Path)
			return next(c)
		}
	})
	e.GET("/action/ws\\:list", func(c echo.Context) error {
		return c.String(http.StatusOK, "should match")
	})
	e.GET("/action/ws\\:nooo", func(c echo.Context) error {
		return c.String(http.StatusOK, "should not match")
	})
	go e.Start(":8080")

	time.Sleep(time.Second / 2)
	res, err := req.Get("http://localhost:8080/action/ws:list", req.Param{})
	assert.NoError(t, err)
	t.Log(res) // 404 not found
}
```

### Version/commit

4.6.1
