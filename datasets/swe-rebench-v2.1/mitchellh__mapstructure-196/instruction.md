Support struct wrapped in interface as target for decoding
Similar to #186, mapstructure is not handling structs assigned to interfaces:

```go
var cc interface{}
cc = struct{ Foo, Bar string }{}

decoderConfig := &mapstructure.DecoderConfig{Result: &cc, ErrorUnused: true}
decoder, err := mapstructure.NewDecoder(decoderConfig)
if err != nil {
	log.Fatal(err)
}

conf := map[string]string{
	"foo": "bar",
	"bar": "baz",
}

if err := decoder.Decode(conf); err != nil {
	log.Fatal(err)
}
```

Will give

    * '' has invalid keys: bar, foo

Would this be something worthwile to address with a PR or are there constraints that would prevent handling this case?

### Additional contract requirements

When decoding a map into an interface that currently holds a non-pointer struct, decoding must populate that concrete struct value and return without error. When `ErrorUnused` is enabled, input keys matching fields of that struct must be treated as used rather than reported as invalid.
