Panic (nil dereference) when writing to GenericBuffer[any] without schema
As the title states, the library panics with a nil pointer dereference when attempting to write to a `GenericBuffer[any]` if no schema is provided.

```
# ./parquet_panic
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0x6cf160]

goroutine 1 [running]:
github.com/segmentio/parquet-go.(*Schema).Deconstruct(0x0, {0x0?, 0x0, 0x0}, {0x71bd00?, 0xc0001191b0?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/schema.go:231 +0x120
github.com/segmentio/parquet-go.(*GenericBuffer[...]).writeRows(0xc000122090, {0xc0001191b0, 0x1, 0x0})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/buffer_go18.go:154 +0x1b2
github.com/segmentio/parquet-go.(*GenericBuffer[...]).Write(0x0?, {0xc0001191b0?, 0x0?, 0x721c60?})
	/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220914222423-67dbe8d21ca5/buffer_go18.go:125 +0x47
main.main()
	/parquet_panic/main.go:14 +0x91
```

Minimal reproduction code:
```go
package main

import (
	parquet "github.com/segmentio/parquet-go"
)

type TestType struct{}

func main() {
	buffer := parquet.NewGenericBuffer[any]()

	data := make([]any, 1)
	data[0] = TestType{}
	_, _ = buffer.Write(data)
}
```
