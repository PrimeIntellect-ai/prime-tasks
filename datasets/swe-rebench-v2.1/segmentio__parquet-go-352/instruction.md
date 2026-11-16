Panic when writing to GenericBuffer[any]
As the title states, when using a `GenericBuffer[any]` with a provided schema and attempting to write, the library panics with the following error:

```
# ./parquet_panic
panic: reflect: call of reflect.Value.Field on interface Value

goroutine 1 [running]:
reflect.Value.Field({0x731d80?, 0xc0000172c0?, 0x10?}, 0x725620?)
	/usr/local/go/src/reflect/value.go:1266 +0xe5
github.com/segmentio/parquet-go.(*structField).Value(0x7?, {0x731d80?, 0xc0000172c0?, 0x1f?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/schema.go:439 +0x1d7
github.com/segmentio/parquet-go.deconstructFuncOfGroup.func1({0x0?, 0xc0000172c0?, 0x40ed3f?}, {0xf0?, 0x1d?, 0xc?}, {0x731d80?, 0xc0000172c0?, 0x782f80?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/row.go:486 +0x146
github.com/segmentio/parquet-go.(*Schema).Deconstruct(0xc00007e240, {0x0?, 0x0, 0x0}, {0x71bd00?, 0xc0000172c0?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/schema.go:232 +0x148
github.com/segmentio/parquet-go.(*GenericBuffer[...]).writeRows(0xc000018120, {0xc0000172c0, 0x1, 0x0})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/buffer_go18.go:154 +0x1b2
github.com/segmentio/parquet-go.(*GenericBuffer[...]).Write(0xc0000c1f60?, {0xc0000172c0?, 0xc0000c1f70?, 0x408059?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/buffer_go18.go:125 +0x47
main.main()
	/parquet_panic/main.go:17 +0xf1
```

Minimal reproduction code:

```go
package main

import (
	parquet "github.com/segmentio/parquet-go"
)

type TestType struct {
	Key int
}

func main() {
	schema := parquet.SchemaOf(TestType{})
	buffer := parquet.NewGenericBuffer[any](schema)

	data := make([]any, 1)
	data[0] = TestType{Key: 0}
	_, _ = buffer.Write(data)
}
```
