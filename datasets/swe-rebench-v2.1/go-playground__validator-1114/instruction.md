Url validation accepts `https:` as valid url.
- [ √ ] I have looked at the documentation [here](https://pkg.go.dev/github.com/go-playground/validator/v10#section-documentation) first?
- [ √ ] I have looked at the examples provided that may showcase my question [here](/_examples)?

### Package version eg. v9, v10:

v10

### Issue, Question or Enhancement:

Url validation accepts `https:` as valid url.

### Code sample, to showcase or reproduce:

```go
package main

import (
	"fmt"

	"github.com/go-playground/validator/v10"
)

type User struct {
	Url string `json:"url" validate:"required,url"`
}

func main() {
	validate := validator.New()
	user := &User{Url: "https:"}
	err := validate.Struct(user)
	if err != nil {
		panic(err)
	}
	fmt.Println("ok")
}
```
This code results in ok print, but expected result should be panic on error
