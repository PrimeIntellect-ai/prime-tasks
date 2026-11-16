Serializing struct with embedded interface results in malformed json
Example:
```
type I interface {
	Foo()
}

type A struct {
	I
	Val string
}

func TestStructWithEmbeddedInterface(t *testing.T) {
	var s A
	s.Val = "456"

	j1, _ := json.Marshal(s)  // This uses encoding/json.
	fmt.Println("expected", string(j1))

	j2, _ := goccyjson.Marshal(s)  // This uses this library.
	fmt.Println("actual", string(j2))
}
```

The code above will generate a json string that is not valid.

Expected result (using `encoding/json`):
`{"I":null,"Val":"456"}`

Actual result:
`{null,"Val":"456"}`

This can be reproduced with:
`github.com/goccy/go-json v0.10.0`
