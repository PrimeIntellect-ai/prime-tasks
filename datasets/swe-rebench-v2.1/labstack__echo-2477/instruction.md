Data race in parallel test with RequestLogger middleware
### Issue Description

I get a `WARNING: DATA RACE` when running parallel tests with the "-race" flag in `RequestLoggerConfig`.



### Checklist

- [+] Dependencies installed
- [+] No typos
- [+] Searched existing issues and docs

### Expected behaviour

No data race in parallel tests

### Actual behaviour

Data race in parallel tests

### Steps to reproduce

Save code below to `bug_test.go`:

```go
package bug

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

func New() *echo.Echo {
	e := echo.New()
	e.Pre(
		middleware.RequestLoggerWithConfig(
			middleware.RequestLoggerConfig{},  // just example
		),
	)
	return e
}

func TestB(t *testing.T) {
	t.Parallel()

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	res := httptest.NewRecorder()
	New().ServeHTTP(res, req)
}

func TestA(t *testing.T) {
	t.Parallel()

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	res := httptest.NewRecorder()
	New().ServeHTTP(res, req)
}
```

Run: `go test -race bug_test.go`.

### Working code to debug

See "Steps to reproduce".

### Version/commit
v4.10.2

### Reason/Solution

[HIDDEN]
