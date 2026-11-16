[bug] []byte conversion
@caarlos0 I have a custom func for `[]bytes`, after this [PR](https://github.com/caarlos0/env/pull/223) I got the following error:
```bash
panic: env: parse error on field "Abc" of type "[]uint8": strconv.ParseUint: parsing "asdasd": invalid syntax
```
my mapping
```
Abc       []byte `env:"ABC" envDefault:"asdasd"`
```
my custom func
```go
func parseSliceOfBytes(c *Config) {
	if err := env.ParseWithFuncs(c, map[reflect.Type]env.ParserFunc{
		reflect.TypeOf([]byte{0}): func(v string) (interface{}, error) {
			return []byte(v), nil
		},
	}); err != nil {
		panic(err)
	}
}
```

### Additional contract requirements

When `ParseWithFuncs` parses nested structs, the supplied custom parser map remains in effect for their fields as well. Thus a registered parser for `[]byte` is used for `[]byte` fields in nested structs, including values supplied by defaults.
