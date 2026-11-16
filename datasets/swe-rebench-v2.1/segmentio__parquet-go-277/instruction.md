Panic with generic reader and `any`
Hey, it says in the API docs:

> The type parameter T should be a map, struct, or any.

But I'm trying this with the following code:

```go
pFile, err := os.Open("./resources/pokemon_fans.parquet")
require.NoError(t, err)

pRdr := parquet.NewGenericReader[any](pFile)
```

And it panics with "panic: runtime error: invalid memory address or nil pointer dereference", pointing to: `github.com/segmentio/parquet-go/schema.go:126`. Using the now deprecated `NewReader` function seems to work as I'd expect.
