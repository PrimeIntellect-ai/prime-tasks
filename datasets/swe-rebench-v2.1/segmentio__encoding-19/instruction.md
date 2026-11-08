Decoder hangs when decoding invalid json
```go
func TestHangingDecoder(t *testing.T) {
	b := []byte(`{
	"userId": "blah",
	}`)

	d := NewDecoder(bytes.NewReader(b))

	var a struct {
		UserId string `json:"userId"`
	}
	err := d.Decode(&a)
	if err == nil {
		t.Fatal("should have errored")
	}
}
```

This test hangs on master. Light on details for now, will add more when I have them.

Looks like it's an issue in Decoder. It works fine with `Unmarshal`:

```go
// this works
func TestHangingDecoder(t *testing.T) {
	b := []byte(`{
	"userId": "blah",
	}`)
	var a struct {
		UserId string `json:"userId"`
	}
	err := Unmarshal(b, &a)
	if err == nil {
		t.Fatal("should have errored")
	}
}
```
