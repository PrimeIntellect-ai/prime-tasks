Type error when using DecodeHook to decode into interface
**What version of are you using (git log -1 --format=oneline)?**
fe40af7a9c397fa3ddba203c38a5042c5d0475ad (HEAD -> master, tag: v1.1.1, origin/master, origin/HEAD) Update CHANGELOG

**What did you do?**
Run attached test:
```go
package mapstructure_test

import (
	"reflect"
	"testing"

	"github.com/mitchellh/mapstructure"
)

type DecodeInto struct {
	Test Interface
}

type Interface interface {
	DoStuff()
}

type ImplementsInterface struct {
	Name string
}

func (i *ImplementsInterface) DoStuff() {}

func TestInterfaceDecodeHook(t *testing.T) {
	in := map[string]string{"test": "test"}
	decodeInto := new(DecodeInto)

	config := &mapstructure.DecoderConfig{
		DecodeHook: stringToInterfaceDecodeHook,
		Result:     decodeInto,
	}
	decoder, _ := mapstructure.NewDecoder(config)
	err := decoder.Decode(in)
	if err != nil {
		t.Errorf("Decode returned error: %s", err)
	}
}

func stringToInterfaceDecodeHook(from, to reflect.Type, data interface{}) (interface{}, error) {
	if from.Kind() != reflect.String {
		return data, nil
	}

	if to != reflect.TypeOf((*Interface)(nil)).Elem() {
		return data, nil
	}
	// Ensure interface is satisfied
	var impl Interface = &ImplementsInterface{data.(string)}
	return impl, nil
}
```

**What did you expect to see?**
I expected the test to pass.

**What did you see instead?**
```
Running tool: /usr/local/opt/go@1.11/bin/go test -timeout 30s github.com/mitchellh/mapstructure -run ^TestInterfaceDecodeHook$

--- FAIL: TestInterfaceDecodeHook (0.00s)
    /Users/sebastianwidmer/go/src/github.com/mitchellh/mapstructure/mapstructure_interface_test.go:35: Decode returned error: 1 error(s) decoding:

        * 'Test' expected type 'mapstructure_test.Interface', got 'mapstructure_test.ImplementsInterface'
FAIL
FAIL	github.com/mitchellh/mapstructure	0.009s
Error: Tests failed.
```

This happens since upgrading to v1.1.1 to all our hooks decoding into interfaces. Will dig deeper into the changes tomorrow and try to create a pull request.
