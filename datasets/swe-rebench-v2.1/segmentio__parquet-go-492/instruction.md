WriteBooleans appears to be broken (panic)
I am using the optimizing writes method to write many values at once:

```
if n, err = columns[i].(parquet.BooleanWriter).WriteBooleans(elements); err != nil {
    return err
}
```

This results in a panic:

```
panic: runtime error: slice bounds out of range [:41877] with capacity 4096

goroutine 1 [running]:
github.com/segmentio/parquet-go.(*booleanColumnBuffer).writeValues(0xc0029d0140, {{0xc014d22000?, 0x2b724e18?, 0xc0000c7bf8?}}, {0x5d?, 0xb1?, 0x0?})
	/Users/jonathannovak/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20230309140036-b6d0a6236da6/column_buffer.go:833 +0x3c5
github.com/segmentio/parquet-go.(*booleanColumnBuffer).WriteBooleans(0xc0000999b0?, {0xc014d22000?, 0x51ca1, 0xc000108000?})
	/Users/jonathannovak/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20230309140036-b6d0a6236da6/column_buffer.go:818 +0x45
```

I should note that this issue does NOT occur writing doubles, int64s, and WriteByteArrays.
