Better document/warn requirement for unsetting `doc.Servers`
In https://github.com/deepmap/oapi-codegen/blob/5a337911b060aad7130b05ad1819cfd3b73884f4/examples/petstore-expanded/gin/petstore.go#L26-L28, and other cases we're getting the Middleware

```go
	// Clear out the servers array in the swagger spec, that skips validating
	// that server names match. We don't know how this thing will be run.
	swagger.Servers = nil
```

I recommend we log a warning if we see that `Servers != nil`.

This won't break anyone's builds or expectations if they're needing it, but will make it clear that this could be a problem.

It's a problem I've hit several times and so have others I've worked with, so we should try and preemptively alert folks!

### Additional contract requirements

- The request-validation middlewares for net/http (chi), echo and gin, when created without custom options from an OpenAPI spec whose `Servers` field is non-nil, must write a warning to the standard `log` package output. The warning text must name the `Servers` field.
- Creating the middleware from a spec whose `Servers` field is nil must not write anything to the standard `log` output.
- The warning must not change request validation: a valid request is still passed to the next handler, and a request missing a required query parameter is still rejected with HTTP 400.
