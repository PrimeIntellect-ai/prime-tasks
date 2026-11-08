Squash decoder option squashes everything
The squash decoder option should squash only embedded structs as documented, but it squashes all struct fields regardless of being embedded or not.

The proposed fix is trivial and was implemented in one of the similar PRs (https://github.com/mitchellh/mapstructure/pull/134): [HIDDEN]

However, this would be a breaking change since some users might rely on the "squash everything" behavior of the option already. I will create a PR with a straightforward fix but not sure if such a breaking change is acceptable in this repo.

Alternatively, the `config.Squash` option could be complemented with something along the lines of `config.SquashEmbedded`.

Test case to demonstrate the issue:
```go
package mapstructure_test

import (
	"testing"

	"github.com/mitchellh/mapstructure"
)

type (
	Config struct {
		Nested        // expected to be squashed
		Named  Nested // expected to not be squashed
	}
	Nested struct {
		Value string
	}
)

func TestDecode_SquashOption(t *testing.T) {
	input := map[string]interface{}{
		"Value": "foo",
		"Named": map[string]interface{}{
			"Value": "bar",
		},
	}

	result := Config{}
	decoder, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{
		Result: &result,
		Squash: true,
	})
	if err != nil {
		t.Fatalf("got an err: %s", err.Error())
	}

	err = decoder.Decode(input)
	if err != nil {
		t.Fatalf("got an err: %s", err.Error())
	}

	if result.Nested.Value != "foo" {
		t.Errorf("Nested.Value value should be 'foo': %#v", result.Nested.Value)
	}
	if result.Named.Value != "bar" {
		t.Errorf("Named.Value value should be 'bar': %#v", result.Named.Value)
	}
}

func TestDecodeFrom_SquashOption(t *testing.T) {
	input := Config{
		Nested: Nested{Value: "foo"},
		Named:  Nested{Value: "bar"},
	}

	result := map[string]interface{}{}
	decoder, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{
		Result: &result,
		Squash: true,
	})
	if err != nil {
		t.Fatalf("got an err: %s", err.Error())
	}

	err = decoder.Decode(input)
	if err != nil {
		t.Fatalf("got an err: %s", err.Error())
	}

	if v, ok := result["Value"]; !ok {
		t.Error("Value (from an embedded field) should be present in map")
	} else if v != "foo" {
		t.Errorf("Value (from an embedded field) should be 'foo': %#v", v)
	}

	if v, ok := result["Named"]; !ok {
		t.Error("Named field should be present in map")
	} else {
		named := v.(map[string]interface{})
		if v, ok := named["Value"]; !ok {
			t.Error("Named: Value should be present in map")
		} else if v != "bar" {
			t.Errorf("Named: Value should be 'bar': %#v", v)
		}
	}
}
```

### Additional contract requirements

- With `Squash` enabled, embedded struct fields are flattened, while named struct fields remain nested, both when decoding into a struct and when decoding a struct into a map.
