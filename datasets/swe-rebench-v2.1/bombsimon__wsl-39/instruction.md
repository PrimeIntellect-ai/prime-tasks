Correct Example syntax triggering "block should not end with a whitespace (or comment)"
[Example](https://golang.org/pkg/testing/#hdr-Examples) functions must end with comments, but wsl doesn't like that very much:

Here's a snippet that's failing for me in [go-which](https://github.com/hairyhenderson/go-which):

```go
func ExampleWhich() {
        path := Which("sh")
        fmt.Printf("Found sh at: %s", path)

        // Output: Found sh at: /bin/sh
}
```

```console
$ wsl which_test.go
which_test.go:124: block should not end with a whitespace (or comment)
```

I'm thinking wsl should probably ignore this particular check in `Example` tests.

### Additional contract requirements

- A Go function named as an `Example` must not receive the block-end whitespace/comment diagnostic solely because its required output comment appears at the end of its body.
- The block-end whitespace/comment diagnostic remains applicable to non-Example functions when they end with whitespace or a comment.
- Other lint diagnostics continue to apply inside Example functions; exempting the ending output comment must not suppress unrelated violations.
