Parameterized routes return 404 after v4.1.13
### Issue Description

The latest release `v4.1.13` introduces a bug relat4ed to #1466 where parameterized routes sometimes return 404 for certain routes.

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Expected behaviour

In the code shared below, if we access the route `/users/sharewithme/profile` or `/users/sharewithme/upload/self`, it's expected that the route would resolve correctly and not return 404 and the following code would return `sharewithme`; `sharewithme` and `self` respectively:

```go
// for route /users/sharewithme/profile
username := c.Param("username") // should return sharewithme

// for route /users/sharewithme/upload/self
username := c.Param("username")
type := c.Param("type")
```

### Actual behaviour

The routes mentioned above fail to resolve and instead return a 404

### Steps to reproduce

Run the code shared with the latest release and try the URLs mentioned above

### Working code to debug

```go
package main

import (
	"fmt"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"log"
	"net/http/httputil"
	"strings"
)

func main() {
	e := echo.New()

	RegisterAPIRoutes(e)

	e.Logger.Fatal(e.Start(":1234"))
}

func RegisterAPIRoutes(e *echo.Echo) {
	e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
		AllowOrigins:  []string{"*"},
		AllowMethods:  []string{echo.GET, echo.PUT, echo.POST, echo.DELETE},
		AllowHeaders:  []string{echo.HeaderContentType, echo.HeaderAuthorization},
		ExposeHeaders: []string{echo.HeaderAuthorization},
	}))

	e.POST("/users/signup", myFunc)
	e.POST("/users/signup/bulk", myFunc)
	e.POST("/users/signup/engcom", myFunc)
	e.POST("/users/surveysignup", myFunc)

	e.GET("/users/:username", myFunc)
	e.GET("/users/:username/likes/projects/ids", myFunc)
	e.GET("/users/:username/profile", myFunc)
	e.GET("/users/:username/uploads/:type", myFunc)

	e.GET("/interests/:name/users", myFunc)
	e.GET("/skills/:name/users", myFunc)
}

func myFunc(c echo.Context) error {
	var builder strings.Builder

	log.Println(c.Request())

	reqDump, _ := httputil.DumpRequest(c.Request(), true)

	builder.Write(reqDump)
	for _, name := range c.ParamNames() {
		builder.WriteString(fmt.Sprintf("Parameter: %s | Value: %s\n", name, c.Param(name)))
	}

	return c.String(200, builder.String())
}
```

### Version/commit
`v4.1.13`

### Additional contract requirements

- For the two-parameter case, the intended request path is `/users/sharewithme/uploads/self`, matching the plural `/uploads/:type` route registered in the example. It must resolve with `username=sharewithme` and `type=self`.
