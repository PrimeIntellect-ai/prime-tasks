Param value is blank after v4.1.12
### Issue Description

The latest release `v4.1.12` introduces a bug where a param value is returned as a blank string.

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Expected behaviour
If we run the code and access `/users/sharewithme`, it's expected that the following code would return `sharewithme`
```go
     param := c.Param("username")
     // param should have value "sharewithme"
```

### Actual behaviour

The current release returns blank string

### Steps to reproduce

Run the code below and try the url as demonstrated above...+

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
	e.POST("/users/survey", myFunc)

	e.GET("/users/:username", myFunc)

	e.GET("/interests/:name/users", myFunc)
	e.GET("/skills/:name/users", myFunc)
}

func myFunc(c echo.Context) error {
	var builder strings.Builder

	log.Println(c.Request())

	reqDump, _ := httputil.DumpRequest(c.Request(), true)

	builder.Write(reqDump)
	for _, name := range c.ParamNames() {
		builder.WriteString(fmt.Sprintf("Parameter: %s | Value: %s", name, c.Param(name)))
	}

	return c.String(200, builder.String())
}

```

### Version/commit
`v4.1.12`
