Unexported function on the Transport interface prevents mocking
In `v1.4.5` the `Transport` interface gained the unexported function `setContext(ctx context.Context)`. This prevents it from being mocked in projects that want to add tests that confirm the library is being used correctly.

This is done in a similar way to the `TestTransport` in `client_test.go`. Trying to define a similar struct in another project will result in the following error (regardless of whether the new function is defined or not)

```
cannot use transport (variable of type *mock.TestTransport) as type "github.com/rollbar/rollbar-go".Transport in assignment:
	*mock.TestTransport does not implement "github.com/rollbar/rollbar-go".Transport (missing setContext method)
```
