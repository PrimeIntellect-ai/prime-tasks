Bug: useless code generated for optional query parameters
This was found in the gorilla-server generator, I don't know if this also happens for other server generators.

Generated code looks as follows:

```go
// ------------- Optional query parameter "name" -------------
if paramValue := r.URL.Query().Get("name"); paramValue != "" {
    // this is empty
}

// BindQueryParameter
```

The `if` block has an empty body. I'm not sure if code is missing here, or if the whole `if` condition is superfluous.

### Additional contract requirements

- For the gorilla server generator, an optional query parameter that needs no handling beyond its standard binding (for example a plain string parameter) must not produce an `if` block with an empty body in the generated handler. The parameter must still be bound into the operation's params struct, so a request carrying the parameter receives its value.
