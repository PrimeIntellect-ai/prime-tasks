timeout middleware returns wrong HTTP status code
### Issue Description
When using the timeout middleware function the HTTP status codes do not work as expected. Returning an error in the actual handler function results in the status code `200` independent of the implementation of the error handler.

### Expected behaviour
If the handler function returns an error, the HTTP status code should be handled by the error handler and not modified by the underlying middleware. In case of the `echo.HTTPError` it should also use the associated status code.

### Actual behaviour
Returning an error results in a `200` status code. Writing a result from the handler such as `c.JSON(..)` etc. results in the expected HTTP response but prints an error log to the stdout. (see below for example)

### Steps to reproduce
The following example is a minimum example that can be used to reproduce the behaviour using just echo `v4.2.1`. In this example the timeout does not really matter. It is intentionally set to a very high threshold. For a `/test` call the server raises an error because it just can't find what it's looking for 😃

```go
package main

import (
	"log"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

func main() {
	e := echo.New()
	e.Use(middleware.TimeoutWithConfig(middleware.TimeoutConfig{
		Timeout: 30 * time.Minute, // unnecessary high timeout for test
	}))
	e.GET("/test", func(_ echo.Context) error {
		return echo.NewHTTPError(http.StatusNotFound, "just not there")
	})
	log.Panic(e.Start(":8080"))
}
```
Calling the server with `curl -i http://localhost:8080/test` results in:
```
HTTP/1.1 200 OK
Date: Wed, 10 Mar 2021 13:54:25 GMT
Content-Length: 29
Content-Type: text/plain; charset=utf-8

{"message":"just not there"}
```
The body of the response reflects the error message defined in the handler but the HTTP status code is wrong. Removing the timeout middleware results in the expected behaviour:
```
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=UTF-8
Date: Wed, 10 Mar 2021 13:56:47 GMT
Content-Length: 29

{"message":"just not there"}
```
---
Independent of wrong HTTP status codes in case of an error the log will always print the following error message.
```
echo: http: superfluous response.WriteHeader call from github.com/labstack/echo/v4.(*Response).WriteHeader (response.go:63)
```
#### Analysis

After reading through the code a little bit my first analysis would point to the `http.TimeoutHandler` as the root problem here. Within the handler it writes the status code header whether there is an error or not (https://github.com/golang/go/blob/master/src/net/http/server.go#L3322). The default case for not timed out requests is status code `200`. [HIDDEN] This results in the error message printed to the stdout. If the handler function is a success the `http.TimeoutHandler` will be the second one to try and set the status code header. In both cases there are two places in the code that try to write the status code header which is not possible. I hope this was kind of understandable.

My personal opinion is that `http.TimeoutHandler` might not be the best fit for a middleware. It is designed to decorate an existing handler in the standard golang sdk. Also it attempts to write the status code and the body depending on the outcome of the handler function. In the echo environment I feel this is rather uncommon. The current middleware implementation also needs a workaround to report a potential error out of this using the `echoHandlerFuncWrapper`.

### Version/commit

echo version: `v4.2.1`
golang version: `go version go1.16 darwin/amd64`
