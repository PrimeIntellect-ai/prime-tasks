404 when using dynamic routing
- With issues:
  - Use the search tool before opening a new issue.
  - Please provide source code and commit sha if you found a bug.
  - Review existing issues and provide feedback or react to them.

## Description
It will bring 404 problem when using dynamic routing(*,:) like below , by calling http://localhost:8080/all. It seemed can not match the path with prefix 'a', such as 'all'.

<!-- Description of a problem -->

## How to reproduce

<!-- The smallest possible code example to show the problem that can be compiled, like -->
```
package main

import (
	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/aa/*xx", newHandler("/aa/*xx"))
	r.GET("/ab/*xx", newHandler("/ab/*xx"))
	r.GET("/:cc", newHandler("/:cc"))

	r.Run() // listen and serve on 0.0.0.0:8080
}

func newHandler(t string) func(c *gin.Context) {
	return func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": t,
		})
	}
}
```

## Expectations

<!-- Your expectation result of 'curl' command, like -->
```
$ curl http://localhost:8080/all
/:cc
```

## Actual result

<!-- Actual result showing the problem -->
```
$ curl http://localhost:8080/all
404 page not found
```

## Environment

- go version:
- gin version (or commit ref): 1.7.2
- operating system:

### Additional contract requirements

- For route-tree matching, `/all` matched by `/:cc` must capture `cc` as `ll`; `/all/cc` matched by `/:cc/cc` must capture `cc` as `ll`; and `/a/cc` matched by `/:cc/cc` must capture `cc` as the empty string.
