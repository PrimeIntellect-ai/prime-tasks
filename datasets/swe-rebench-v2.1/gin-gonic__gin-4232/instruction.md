`gin.Error` doesn't implement `Unwrap` method for non-pointers
I expect following code to print the wrapped error in both pointer and non-pointer uses. But it prints nil when you use it without pointer

```go
package main

import (
	"errors"
	"fmt"

	"github.com/gin-gonic/gin"
)

func main() {
	err := gin.Error{Err: errors.New("test error")}
	fmt.Println(errors.Unwrap(err))  // prints nil
	fmt.Println(errors.Unwrap(&err)) // prints "test error" correctly
}
```

https://github.com/gin-gonic/gin/pull/631 removed pointer from `Error()` receiver to make `gin.Error` usable without pointer but [HIDDEN]

### Additional contract requirements

- Calling `errors.Unwrap` with a non-pointer `gin.Error` must return the underlying error stored in its `Err` field. Pointer use must continue to return that underlying error.
