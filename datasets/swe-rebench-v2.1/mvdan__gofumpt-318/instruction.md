Panic when missing go directive in a go.mod
`gofumpt` panics when the `go` directive is missing in a `go.mod` file.

For example, we get a panic when trying to run `gofumpt` on the repo [`google/uuid`](https://github.com/google/uuid) (latest v1.6.0), which doesn't have the `go` directive in [it](https://github.com/google/uuid/blob/v1.6.0/go.mod).

```sh
❯ go run mvdan.cc/gofumpt@latest -w .
panic: invalid Go version: "go"

goroutine 6 [running]:
mvdan.cc/gofumpt/format.File(0x14000288000, 0x1400029e000, {{0x100348354, 0x2}, {0x140000146a8, 0x16}, 0x0})
        /Users/Oleksandr_Redko/go/pkg/mod/mvdan.cc/gofumpt@v0.7.0/format/format.go:99 +0x23c
main.processFile({0x140001ce498, 0x6}, {0x1003f1068, 0x140001da270}, {0x0?, 0x0?}, 0x14000028f20, 0x0)
        /Users/Oleksandr_Redko/go/pkg/mod/mvdan.cc/gofumpt@v0.7.0/gofmt.go:313 +0x23c
main.gofmtMain.func4.1(0x0?)
        /Users/Oleksandr_Redko/go/pkg/mod/mvdan.cc/gofumpt@v0.7.0/gofmt.go:529 +0x40
main.(*sequencer).Add.func2()
        /Users/Oleksandr_Redko/go/pkg/mod/mvdan.cc/gofumpt@v0.7.0/gofmt.go:191 +0x48
created by main.(*sequencer).Add in goroutine 1
        /Users/Oleksandr_Redko/go/pkg/mod/mvdan.cc/gofumpt@v0.7.0/gofmt.go:190 +0x1a8
exit status 2
```

The [documentation](https://go.dev/ref/mod#go-mod-file-go) states, that "If the go directive is missing, go 1.16 is assumed".
