Make Log a method of Client
This a feature request.

Quite happy with Rollbar and its Go library, but we do miss the option to have `rollbar.Log` available to use with any client and not only the default one.

As it is right now we have to wrap rollbar's clients in our own struct that implements a copy of `rollbar.Log` to emulate the behaviour around requests and error attributes.

This would be ideal:

```go
import "github.com/rollbar/rollbar-go"

rb_client := rollbar.New(...)
// stuff happens
rb_client.Log(error, request, ...)
```
