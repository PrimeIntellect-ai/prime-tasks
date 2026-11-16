funcr: invalid json when omitting fields
Hello !

When using `funcr` implementation with JSON formatter, produced JSON is invalid when omitting fields using `json` struct tag.

## How to reproduce

[Go Playground](https://go.dev/play/p/TM8lUdSVyIV)

```go
type Foo struct {
	Bar string `json:"-"`
	Baz string `json:"baz"`
}

func main() {
	logger := funcr.NewJSON(
		func(obj string) { fmt.Println(obj) },
		funcr.Options{},
	)
	logger.Info("", "foo", Foo{})
}
```

### Expected output

```json
{"logger":"","level":0,"msg":"","foo":{"baz":""}}
```

### Got output

```json
{"logger":"","level":0,"msg":"","foo":{,"baz":""}}
```

Notice the extra comma before `baz` key.

A quick investigation pointed this [line](https://github.com/go-logr/logr/blob/v1.2.3/funcr/funcr.go#L481) as the potential issue.

Thanks for your help !
