Slice out of bounds panic when decoding truncated JSON
Hi,

I'm getting the following panic when decoding `{"\u` which is invalid but shouldn't cause a panic:

```
testing.go:1356: panic: runtime error: slice bounds out of range [:8] with capacity 5
    goroutine 9 [running]:
    runtime/debug.Stack()
    	/usr/lib/go-1.19/src/runtime/debug/stack.go:24 +0xdb
    testing.tRunner.func1()
    	/usr/lib/go-1.19/src/testing/testing.go:1356 +0x1f2
    panic({0x724b60, 0xc00001c150})
    	/usr/lib/go-1.19/src/runtime/panic.go:884 +0x212
    github.com/goccy/go-json/internal/decoder.decodeKeyCharByUnicodeRune({0xc0000181e4, 0x5, 0x5}, 0x4)
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/internal/decoder/struct.go:165 +0x818
    github.com/goccy/go-json/internal/decoder.decodeKeyCharByEscapedChar({0xc0000181e4, 0x5, 0x5}, 0x3)
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/internal/decoder/struct.go:201 +0x54f
    github.com/goccy/go-json/internal/decoder.decodeKeyByBitmapUint8(0xc0000000a0, {0xc0000181e4, 0x5, 0x5}, 0x1)
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/internal/decoder/struct.go:245 +0x649
    github.com/goccy/go-json/internal/decoder.(*structDecoder).Decode(0xc0000000a0, 0xc0000720c0, 0x0, 0x0, 0xc0000181e0)
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/internal/decoder/struct.go:760 +0x8da
    github.com/goccy/go-json.unmarshal({0xc0000181b8, 0x4, 0xc00007e150?}, {0x6f9a20, 0xc0000181e0}, {0x0, 0x0, 0xc0001317d0?})
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/decode.go:47 +0x327
    github.com/goccy/go-json.Unmarshal(...)
    	/home/gbe/go/pkg/mod/github.com/goccy/go-json@v0.10.1-0.20221201165857-a2149a5b2591/json.go:276
    json-u.Fuzz_JSON_Unmarshal.func1(0xc000007520, {0xc0000181b8, 0x4, 0x8})
    	/tmp/json-u/jsonu_test.go:17 +0xa8
    reflect.Value.call({0x6ffba0?, 0x746a68?, 0x13?}, {0x735410, 0x4}, {0xc00007e120, 0x2, 0x2?})
    	/usr/lib/go-1.19/src/reflect/value.go:584 +0x8c5
    reflect.Value.Call({0x6ffba0?, 0x746a68?, 0x51b?}, {0xc00007e120?, 0x88ed10?, 0x8b8720?})
    	/usr/lib/go-1.19/src/reflect/value.go:368 +0xbc
    testing.(*F).Fuzz.func1.1(0x0?)
    	/usr/lib/go-1.19/src/testing/fuzz.go:337 +0x231
    testing.tRunner(0xc000007520, 0xc000128090)
    	/usr/lib/go-1.19/src/testing/testing.go:1446 +0x10b
    created by testing.(*F).Fuzz.func1
    	/usr/lib/go-1.19/src/testing/fuzz.go:324 +0x5b9
```

This is the fuzz test I used:

```
package foobar

import "testing"
import "strings"
import "github.com/goccy/go-json"

func Fuzz_JSON_Unmarshal(f *testing.F) {
	f.Add([]byte(`{}`))
	f.Add([]byte(`{"n": 123}`))
	f.Add([]byte(`{"n": -123}`))

	f.Fuzz(func(t *testing.T, input []byte) {
		var x struct {
			N int32 `json:"n"`
		}

		err := json.Unmarshal(input, &x)
		if err == nil {
			return
		}

		// I was actually looking for a specific error message and just stumbled upon
		// the panic.
		if strings.Contains(err.Error(), "number u") {
			t.Error("found it")
		}
	})
}
```

There are two closed issues with similar panics, one of them while decoding unicode but in a slightly different code path.
