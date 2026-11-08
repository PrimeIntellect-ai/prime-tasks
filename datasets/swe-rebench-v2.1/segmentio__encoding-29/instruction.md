Encoding a struct with error type field fails in various ways
While encoding a struct containing error type I get panic or error(`json: unsupported type: `).

Code:
```go
package main

import (
	"bytes"
	stdjson "encoding/json"
	"errors"
	"fmt"

	segjson "github.com/segmentio/encoding/json"
)

type Column struct {
	Name      string `json:"name"`
	FieldName string `json:"fieldName"`
}

type QueryResult struct {
	Columns []Column                 `json:"columns"`
	Rows    []map[string]interface{} `json:"rows"`
}

type QueryError struct {
	Message string `json:"message"`
	Err     error  `json:"err"`
}

type GroupQueryResult struct {
	GroupId int          `json:"groupId"`
	Data    *QueryResult `json:"data"`
	Error   *QueryError  `json:"error"`
}

func main() {
	v := GroupQueryResult{GroupId: 1, Error: &QueryError{Message: "error message", Err: errors.New("will fail")}}
	fmt.Println("stdEncode: " + stdEncode(v))
	fmt.Println("stdMarshal: " + stdMarshal(v))
	fmt.Println("segEncode: " + segEncode(v))
	fmt.Println("segMarshal: " + segMarshal(v))
}

func stdEncode(v GroupQueryResult) string {
	buf := &bytes.Buffer{}
	enc := stdjson.NewEncoder(buf)
	enc.SetEscapeHTML(true)
	if err := enc.Encode(v); err != nil {
		return err.Error()
	}
	return string(buf.Bytes())
}

func stdMarshal(v GroupQueryResult) string {
	jsonString, err := stdjson.Marshal(v)
	if err != nil {
		return err.Error()
	}
	return string(jsonString)
}

func segEncode(v GroupQueryResult) string {
	buf := &bytes.Buffer{}
	enc := segjson.NewEncoder(buf)
	enc.SetEscapeHTML(true)
	if err := enc.Encode(v); err != nil {
		return err.Error()
	}
	return string(buf.Bytes())
}

func segMarshal(v GroupQueryResult) string {
	jsonString, err := segjson.Marshal(v)
	if err != nil {
		return err.Error()
	}
	return string(jsonString)
}
```


While running given code(go version 1.13.6, library version 0.1.9)
in go playground i get:
```
stdEncode: {"groupId":1,"data":null,"error":{"message":"error message","err":{}}}
stdMarshal: {"groupId":1,"data":null,"error":{"message":"error message","err":{}}}
segEncode: json: unsupported type:
segMarshal: json: unsupported type:
```
on my pc (windows, amd64) i get:
```
stdEncode: {"groupId":1,"data":null,"error":{"message":"error message","err":{}}}
stdMarshal: {"groupId":1,"data":null,"error":{"message":"error message","err":{}}}
runtime: nameOff 0x50e5e0 out of range 0x4ee000 - 0x55cfe3
fatal error: runtime: name offset out of range

goroutine 1 [running]:
runtime.throw(0x53900d, 0x21)
	C:/Go/src/runtime/panic.go:774 +0x79 fp=0xc000089598 sp=0xc000089568 pc=0x42e639
runtime.resolveNameOff(0x557cc0, 0x1000050e5e0, 0x4f7f78)
	C:/Go/src/runtime/type.go:190 +0x2ee fp=0xc000089600 sp=0xc000089598 pc=0x44e68e
reflect.resolveNameOff(0x557cc0, 0x50e5e0, 0xc0000426d0)
	C:/Go/src/runtime/runtime1.go:478 +0x3a fp=0xc000089628 sp=0xc000089600 pc=0x43ccda
reflect.(*rtype).nameOff(...)
	C:/Go/src/reflect/type.go:691
reflect.(*rtype).String(0x557cc0, 0x52b980, 0x557cc0)
	C:/Go/src/reflect/type.go:761 +0x3d fp=0xc000089660 sp=0xc000089628 pc=0x47914d
reflect.(*rtype).ptrTo(0x557cc0, 0x557cc0)
	C:/Go/src/reflect/type.go:1398 +0x90 fp=0xc000089708 sp=0xc000089660 pc=0x47c5d0
reflect.PtrTo(...)
	C:/Go/src/reflect/type.go:1384
github.com/segmentio/encoding/json.constructCodec(0x55a140, 0x557cc0, 0xc0000897b0, 0x0, 0x0, 0x0)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/codec.go:180 +0x14d fp=0xc000089760 sp=0xc000089708 pc=0x4c9d6d
github.com/segmentio/encoding/json.constructCachedCodec(0x55a140, 0x557cc0, 0xc00006ac00, 0x6320e0, 0x100000000000000)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/codec.go:62 +0xe4 fp=0xc0000898c0 sp=0xc000089760 pc=0x4c9b54
github.com/segmentio/encoding/json.Append(0xc00009c000, 0x42, 0x1000, 0x557cc0, 0xc000042230, 0x3, 0x3a, 0xd, 0x5339e9, 0xc00000a517, ...)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/json.go:132 +0x187 fp=0xc000089958 sp=0xc0000898c0 pc=0x4e3107
github.com/segmentio/encoding/json.encoder.encodeInterface(0x3, 0xc00009c000, 0x42, 0x1000, 0xc0000044f0, 0xc00009c000, 0x3b, 0x1000, 0x0, 0x0)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/encode.go:592 +0x70 fp=0xc0000899c0 sp=0xc000089958 pc=0x4e18e0
github.com/segmentio/encoding/json.encoder.encodeStruct(0x3, 0xc00009c000, 0x21, 0x1000, 0xc0000044e0, 0xc00001a280, 0x51cae0, 0x403b34, 0x6132f0, 0xc00006ac00, ...)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/encode.go:557 +0x1e5 fp=0xc000089a80 sp=0xc0000899c0 pc=0x4e1215
github.com/segmentio/encoding/json.constructStructEncodeFunc.func1(0x3, 0xc00009c000, 0x21, 0x1000, 0xc0000044e0, 0x50f8c0, 0x4fd500, 0x0, 0x0, 0x0)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/codec.go:466 +0x6d fp=0xc000089ae8 sp=0xc000089a80 pc=0x4eb35d
github.com/segmentio/encoding/json.encoder.encodePointer(0x3, 0xc00009c000, 0x21, 0x1000, 0xc000004950, 0x55a140, 0x514e80, 0xc000042740, 0xc00009c000, 0x18, ...)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/encode.go:586 +0x10c fp=0xc000089b50 sp=0xc000089ae8 pc=0x4e180c
github.com/segmentio/encoding/json.constructPointerEncodeFunc.func1(0x3, 0xc00009c000, 0x21, 0x1000, 0xc000004950, 0xc00009c000, 0x18, 0x1000, 0x0, 0x0)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/codec.go:704 +0x85 fp=0xc000089bc8 sp=0xc000089b50 pc=0x4eb765
github.com/segmentio/encoding/json.encoder.encodeStruct(0x3, 0xc00009c000, 0x0, 0x1000, 0xc000004940, 0xc00001a180, 0x0, 0x0, 0x0, 0x0, ...)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/encode.go:557 +0x1e5 fp=0xc000089c88 sp=0xc000089bc8 pc=0x4e1215
github.com/segmentio/encoding/json.constructStructEncodeFunc.func1(0x3, 0xc00009c000, 0x0, 0x1000, 0xc000004940, 0x1000, 0xc00009c000, 0xc00009c000, 0xc000089d78, 0x4653ed)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/codec.go:466 +0x6d fp=0xc000089cf0 sp=0xc000089c88 pc=0x4eb35d
github.com/segmentio/encoding/json.Append(0xc00009c000, 0x0, 0x1000, 0x519de0, 0xc000004940, 0x3, 0xc000089f90, 0xc00008a280, 0xc000089e00, 0x409926, ...)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/json.go:135 +0x107 fp=0xc000089d88 sp=0xc000089cf0 pc=0x4e3087
github.com/segmentio/encoding/json.(*Encoder).Encode(0xc000089e60, 0x519de0, 0xc000004940, 0xc000004940, 0x60cf40)
	C:/Users/Mynde/go/pkg/mod/github.com/segmentio/encoding@v0.1.9/json/json.go:372 +0xb9 fp=0xc000089e10 sp=0xc000089d88 pc=0x4e38a9
main.segEncode(0x1, 0x0, 0xc0000044e0, 0x1, 0x1)
	C:/WorkGo/src/segmenio-json-test/main.go:63 +0x119 fp=0xc000089ec0 sp=0xc000089e10 pc=0x4eda09
main.main()
	C:/WorkGo/src/segmenio-json-test/main.go:37 +0x243 fp=0xc000089f60 sp=0xc000089ec0 pc=0x4ed473
runtime.main()
	C:/Go/src/runtime/proc.go:203 +0x21e fp=0xc000089fe0 sp=0xc000089f60 pc=0x43001e
runtime.goexit()
	C:/Go/src/runtime/asm_amd64.s:1357 +0x1 fp=0xc000089fe8 sp=0xc000089fe0 pc=0x456841
```
