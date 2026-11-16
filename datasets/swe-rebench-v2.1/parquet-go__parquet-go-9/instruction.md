panic: reflect: call of reflect.Value.Field on zero Value
I'm trying to read records into a struct that contains a slice of elements with nested struct-pointers and seeing the following panic:

```
panic: reflect: call of reflect.Value.Field on zero Value
```

Below a test I wrote to reproduce the issue. It writes a single record to a parquet file, then tries to read it.

```go
func TestNestedPointer(t *testing.T) {
	type InnerStruct struct {
		InnerField string
	}

	type SliceElement struct {
		Inner *InnerStruct
	}

	type Outer struct {
		Slice []*SliceElement
	}

	in := &Outer{
		Slice: []*SliceElement{
			{
				Inner: &InnerStruct{
					InnerField: "inner-string",
				},
			},
		},
	}

	tmpDir := t.TempDir()
	parquetFile := filepath.Join(tmpDir, "data.parquet")
	f, err := os.Create(parquetFile)
	if err != nil {
		t.Fatal(err)
	}

	pw := parquet.NewGenericWriter[*Outer](f)
	_, err = pw.Write([]*Outer{in})
	if err != nil {
		t.Fatal(err)
	}

	err = pw.Close()
	if err != nil {
		t.Fatal(err)
	}

	err = f.Close()
	if err != nil {
		t.Fatal(err)
	}

	f, err = os.Open(parquetFile)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	pr := parquet.NewGenericReader[*Outer](f)

	out := make([]*Outer, 1)
	_, err = pr.Read(out)
	if err != nil {
		t.Fatal(err)
	}

	pr.Close()
}
```

The code above works as expected if `InnerStruct` is not a pointer in the slice element.

```go
	type SliceElement struct {
		Inner InnerStruct
	}
```

Any suggestions on how to fix this? I can't remove the pointers since I'm using generated protobuf messages which always use pointers. The pointers don't appear to be a problem in other places, only if used in a struct that's part of a slice from what I can tell. Any help with this is appreciated.
