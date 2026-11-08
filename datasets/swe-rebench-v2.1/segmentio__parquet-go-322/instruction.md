Different types returned in same scenario by Writer and Buffer
In a simple scenario where I create a schema with a single bytes column, read the written page and attempt to create a dictionary from the observed type in the column index, I will get a panic depending on which type of writer I used to write the data. My expectation is that regardless of the writer used, I will observe the same behavior.

Here is a test illustrating what I mean:
```go
func TestWriter(t *testing.T) {
	node := parquet.String()
	node = parquet.Encoded(node, &parquet.RLEDictionary)
	g := parquet.Group{}
	g["mystring"] = node
	schema := parquet.NewSchema("test", g)

	rows := []parquet.Row{[]parquet.Value{parquet.ValueOf("hello").Level(0, 0, 0)}}

	var storage bytes.Buffer

	tests := []struct {
		name        string
		getRowGroup func(t *testing.T) parquet.RowGroup
	}{
		{
			name: "NormalWriter",
			getRowGroup: func(t *testing.T) parquet.RowGroup {
				t.Helper()

				w := parquet.NewWriter(&storage, schema)
				_, err := w.WriteRows(rows)
				require.NoError(t, err)
				require.NoError(t, w.Close())

				r := bytes.NewReader(storage.Bytes())
				f, err := parquet.OpenFile(r, int64(storage.Len()))
				require.NoError(t, err)
				return f.RowGroups()[0]
			},
		},
		{
			name: "Buffer",
			getRowGroup: func(t *testing.T) parquet.RowGroup {
				t.Helper()

				b := parquet.NewBuffer(schema)
				_, err := b.WriteRows(rows)
				require.NoError(t, err)
				return b
			},
		},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			rowGroup := testCase.getRowGroup(t)

			chunk := rowGroup.ColumnChunks()[0]
			idx := chunk.ColumnIndex()
			val := idx.MinValue(0)
			columnType := chunk.Type()

			_ = columnType.NewDictionary(0, 1, columnType.NewValues(val.Bytes(), []uint32{0, uint32(len(val.Bytes()))}))
		})
	}
}
```

In the `Buffer` case, the test panics [HIDDEN]:
```
panic: cannot convert values of type INT32 to type BYTE_ARRAY [recovered]
        panic: cannot convert values of type INT32 to type BYTE_ARRAY

goroutine 21 [running]:
testing.tRunner.func1.2({0x10524bfc0, 0x140002f8310})
        /opt/homebrew/opt/go/libexec/src/testing/testing.go:1396 +0x1c8
testing.tRunner.func1()
        /opt/homebrew/opt/go/libexec/src/testing/testing.go:1399 +0x378
panic({0x10524bfc0, 0x140002f8310})
        /opt/homebrew/opt/go/libexec/src/runtime/panic.go:884 +0x204
github.com/segmentio/parquet-go/encoding.(*Values).assertKind(...)
        /Users/asubiotto/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220802221544-d84ed320251d/encoding/values.go:56
github.com/segmentio/parquet-go/encoding.(*Values).ByteArray(0x14000080d28?)
        /Users/asubiotto/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220802221544-d84ed320251d/encoding/values.go:109 +0xb4
github.com/segmentio/parquet-go.newByteArrayDictionary({0x1053250c0?, 0x1057d2778}, 0x0, 0x0?, {0x2, 0x0, {0x1400019ff80, 0x5, 0x8}, {0x0, ...}})
        /Users/asubiotto/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220802221544-d84ed320251d/dictionary.go:680 +0x50
github.com/segmentio/parquet-go.(*stringType).NewDictionary(0x0?, 0x0, 0x1, {0x2, 0x0, {0x1400019ff80, 0x5, 0x8}, {0x0, 0x0, ...}})
        /Users/asubiotto/go/pkg/mod/github.com/segmentio/parquet-go@v0.0.0-20220802221544-d84ed320251d/type.go:915 +0xb8
```

### Additional contract requirements

- For the described column, the type observed from row groups produced by `Writer` and `Buffer` must be consistent.
- Creating values from the column-index minimum using the observed column type, and then creating a dictionary from those values, must not panic for either writer.
