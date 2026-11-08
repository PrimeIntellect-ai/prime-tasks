Empty key name when decoding map from struct with only omitempty flag
If a structtag only contains `,omitempty` when decoding a map from a struct, [HIDDEN]. I can't find whether this is defined behavior. If not, I have a PR ready to fix this.

Example:
```go
type Struct struct {
	Username string `mapstructure:",omitempty"`
}

s := Struct{
	Username: "Joe",
}
var m map[string]interface{}
mapstructure.Decode(s, &m)

// Output: map[:Joe]
// Expected output: map[Username:Joe]
fmt.Printf("%+v", m)
```

### Additional contract requirements

- When decoding a struct into a map, a non-empty field tagged `,omitempty` with no explicit tag name must be emitted under its Go field name, not under an empty key.
