Panic caused by omitempty in an embedded struct
This problem can be reproduced with the following code:
```go
package main

import (
	"fmt"

	json "github.com/goccy/go-json"
)

type CustomString string

type EmbedStruct struct {
	CustomString1 CustomString `json:"custom_string1,omitempty"` // causes a panic when zero
}

type MainStruct struct {
	EmbedStruct
	Hello         string       `json:"hello"`
	CustomString2 CustomString `json:"custom_string2,omitempty"` // works without any problems
}

func (m MainStruct) MarshalJSON() ([]byte, error) {
	// substitute is needed to add extra info and avoid recursion
	type substitute MainStruct

	return json.Marshal(struct {
		substitute
		ExtraInfo string `json:"extra_info"`
	}{substitute: substitute(m), ExtraInfo: "test"})
}

func main() {
	v := MainStruct{
		// uncomment this to make it work
		//EmbedStruct: EmbedStruct{
		//CustomString1: "test",
		//},
		Hello: "123",
	}

	res, err := json.Marshal(v)
	fmt.Println(string(res), err)
}
```

Panic information:
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x4f165c]

goroutine 1 [running]:
github.com/goccy/go-json/internal/encoder/vm.Run(0xc0001044e0, {0xc000122800?, 0x0?, 0x0?}, 0x0?)
	github.com/goccy/go-json@v0.9.10/internal/encoder/vm/vm.go:26 +0x7c
github.com/goccy/go-json.encodeRunCode(0xc00012e5d8?, {0xc000122800?, 0x203000?, 0xc000024100?}, 0xc000122c00?)
	github.com/goccy/go-json@v0.9.10/encode.go:310 +0x68
github.com/goccy/go-json.encode(0xc0001044e0, {0x530a20, 0xc0000240c0})
	github.com/goccy/go-json@v0.9.10/encode.go:235 +0x233
github.com/goccy/go-json.marshal({0x530a20, 0xc0000240c0}, {0x0, 0x0, 0xc00012e6c8?})
	github.com/goccy/go-json@v0.9.10/encode.go:150 +0xb9
github.com/goccy/go-json.MarshalWithOption(...)
	github.com/goccy/go-json@v0.9.10/json.go:186
github.com/goccy/go-json.Marshal({0x530a20?, 0xc0000240c0?})
	github.com/goccy/go-json@v0.9.10/json.go:171 +0x2a
main.MainStruct.MarshalJSON({{{0x0, 0x0}}, {0x542a6c, 0x3}, {0x0, 0x0}})
	./main.go:25 +0xaa
github.com/goccy/go-json/internal/encoder.AppendMarshalJSON(0xc000104410, 0xc0001260f0, {0xc000122000, 0x0, 0x400}, {0x537880?, 0xc00007e150?})
	github.com/goccy/go-json@v0.9.10/internal/encoder/encoder.go:430 +0x49f
github.com/goccy/go-json/internal/encoder/vm.appendMarshalJSON(0x0?, 0x0?, {0xc000122000?, 0x0?, 0x0?}, {0x537880?, 0xc00007e150?})
	github.com/goccy/go-json@v0.9.10/internal/encoder/vm/util.go:152 +0x28
github.com/goccy/go-json/internal/encoder/vm.Run(0xc000104410, {0xc000122000?, 0x0?, 0x400?}, 0xc000128000?)
	github.com/goccy/go-json@v0.9.10/internal/encoder/vm/vm.go:271 +0x2673
github.com/goccy/go-json.encodeRunCode(0xc00007ae08?, {0xc000122000?, 0x674e60?, 0xc000024080?}, 0xc000122400?)
	github.com/goccy/go-json@v0.9.10/encode.go:310 +0x68
github.com/goccy/go-json.encode(0xc000104410, {0x537880, 0xc00007e150})
	github.com/goccy/go-json@v0.9.10/encode.go:235 +0x233
github.com/goccy/go-json.marshal({0x537880, 0xc00007e150}, {0x0, 0x0, 0xc00007af40?})
	github.com/goccy/go-json@v0.9.10/encode.go:150 +0xb9
github.com/goccy/go-json.MarshalWithOption(...)
	github.com/goccy/go-json@v0.9.10/json.go:186
github.com/goccy/go-json.Marshal({0x537880?, 0xc00007e150?})
	github.com/goccy/go-json@v0.9.10/json.go:171 +0x2a
main.main()
	./main.go:40 +0x6d
```

What I've noticed so far:
- There's no panic when `type substitute MainStruct` isn't used
- There's no panic when `omitempty` isn't used by `CustomString1` in `EmbedStruct`
- There's no panic when `CustomString1` is non-zero
- It works without any problems when `encoding/json` is used
