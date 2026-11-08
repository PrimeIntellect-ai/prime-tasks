CORS middleware sends empty and/or unnecessary headers
### Issue Description

I have noticed two issues that CORS middleware has:
1. It sends empty `Access-Control-Allow-Origin` header if
    * `Origin` header in the request is missing or
    * `Origin` header is not allowed
2. It sends CORS headers (`Access-Control-*`) even if there is no `Origin` header in the request or provided `Origin` is not allowed. To my understanding if a request is supposed to use CORS it [should have](https://w3c.github.io/webappsec-cors-for-developers) an `Origin` header. I tested this behaviour with [PlayFramework](https://github.com/playframework/playframework) and [Gin](https://github.com/gin-contrib/cors), they are not sending CORS related headers in this case.

### Checklist

- [X] Dependencies installed
- [X] No typos
- [X] Searched existing issues and docs

### Expected behaviour

* CORS middleware should not send empty header `Access-Control-Allow-Origin:`.
* CORS middleware should only provide `Access-Control-*` headers when `Origin` header is provided.

### Actual behaviour

Described in Issue Description section.

### Steps to reproduce

After running the code provided below (in "Working code to debug" part) it can be reproduced with the following curl commands:

#### Empty Access-Control-Allow-Origin when Origin is not allowed:

```shell
curl -X OPTIONS -H "Origin: http://bar.com" -I http://localhost:1323/
HTTP/1.1 204 No Content
Access-Control-Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE
Access-Control-Allow-Origin:
Vary: Origin
Vary: Access-Control-Request-Method
Vary: Access-Control-Request-Headers
Date: Fri, 06 Nov 2020 01:11:30 GMT
```

#### Empty Access-Control-Allow-Origin when Origin is not provided:

```shell
curl -X OPTIONS -I http://localhost:1323/
HTTP/1.1 204 No Content
Access-Control-Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE
Access-Control-Allow-Origin:
Vary: Origin
Vary: Access-Control-Request-Method
Vary: Access-Control-Request-Headers
Date: Fri, 06 Nov 2020 01:12:56 GMT
```

#### Access-Control-* headers when Origin is not provided:

**NOTE**: For this first change middleware line to `e.Use(middleware.CORS())` (by default AllowOrigin is `*`)

```shell
curl -X OPTIONS -I http://localhost:1323/
HTTP/1.1 204 No Content
Access-Control-Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE
Access-Control-Allow-Origin: *
Vary: Origin
Vary: Access-Control-Request-Method
Vary: Access-Control-Request-Headers
Date: Fri, 06 Nov 2020 01:21:06 GMT
```

### Working code to debug

```go
package main

import (
    "net/http"

    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
)

func main() {
    e := echo.New()
    e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
        AllowOrigins: []string{"http://example.com"},
    }))
    e.GET("/", func(c echo.Context) error {
        return c.String(http.StatusOK, "Hello, World!")
    })
    e.Logger.Fatal(e.Start(":1323"))
}
```

### Version/commit

v4.1.17

### Additional contract requirements

- * For an OPTIONS request, the middleware should return HTTP 204 No Content, including when the request has no `Origin` header or its `Origin` is not allowed.
