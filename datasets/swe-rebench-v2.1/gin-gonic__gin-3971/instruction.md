Can UnmarshalParam support custom slice of string
## Feature
Support UnmarshalParam for custom string slice type in tag form.

## Description

<!-- Description of a problem -->
If we define a custom type of string slice and implement the Gin's interface of UnmarshalParam, then we can't get the expected result.

## How to reproduce

<!-- The smallest possible code example to show the problem that can be compiled, like -->
```
package main

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type CustomPath []string

func (b *CustomPath) UnmarshalParam(param string) error {
	elems := strings.Split(param, "/")
	n := len(elems)
	if n < 2 {
		return fmt.Errorf("invalid path: %s", param)
	}

	*b = elems
	return nil
}

type PathRequest struct {
	Paths CustomPath `form:"path"`
}

func main() {
	g := gin.Default()
	g.GET("", func(c *gin.Context) {
		var request PathRequest
		if err := c.ShouldBind(&request); err != nil {
			c.String(http.StatusBadRequest, "request parse err: %v", err)
			return
		}

		c.String(200, "Hello %s", request.Paths)
	})
	g.Run(":9000")
}

```

## Expectations

<!-- Your expectation result of 'curl' command, like -->
```
$ curl 'http://127.0.0.1:9000?path=hello/world'
CustomPath:  [hello world]
```

## Actual result

<!-- Actual result showing the problem -->
```
$ curl 'http://127.0.0.1:9000?path=hello/world'
CustomPath:  [hello/world]
```

## Environment

- go version: go1.22.0 darwin/arm64
- gin version (or commit ref): v1.10.0
- operating system: macOS 13.5

### Additional contract requirements

- A struct field whose type implements `UnmarshalParam(param string) error` must be populated by calling that method with the tagged form or URI value. This applies to both slice-typed and array-typed fields.
- If `UnmarshalParam` returns an error, that error must be propagated to the caller of the binding operation.
