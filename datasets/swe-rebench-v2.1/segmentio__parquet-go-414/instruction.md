Optional slice causes panic
Using `optional` on a slice causes the following panic:
```
panic: reflect: call of reflect.Value.Field on slice Value [recovered]
        panic: reflect: call of reflect.Value.Field on slice Value

goroutine 4 [running]:
testing.tRunner.func1.2({0x104afcc40, 0x1400000eb10})
        /usr/local/go/src/testing/testing.go:1396 +0x1c8
testing.tRunner.func1()
        /usr/local/go/src/testing/testing.go:1399 +0x378
panic({0x104afcc40, 0x1400000eb10})
        /usr/local/go/src/runtime/panic.go:884 +0x204
reflect.Value.Field({0x104aca6c0?, 0x140001f8e70?, 0x104afb6e0?}, 0x70?)
        /usr/local/go/src/reflect/value.go:1266 +0xec
github.com/segmentio/parquet-go.(*structField).Value(0x140000cf600, {0x104aca6c0?, 0x140001f8e70?, 0x10455b72c?})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/schema.go:440 +0x2a8
github.com/segmentio/parquet-go.reconstructFuncOfGroup.func1({0x104aca6c0?, 0x140001f8e70?, 0x140000c1ab8?}, {0x3c?, 0xc0?, 0x87?}, {0x1400000eaf8, 0x1, 0x1})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/row.go:729 +0x340
github.com/segmentio/parquet-go.reconstructFuncOfOptional.func1({0x104aca6c0?, 0x140001f8e70?, 0x140001f8e70?}, {0x18?, 0x0?, 0x0?}, {0x1400000eaf8?, 0x1, 0x1})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/row.go:571 +0x208
github.com/segmentio/parquet-go.reconstructFuncOfGroup.func1({0x104b25120?, 0x140001f8e70?, 0x0?}, {0x70?, 0xfa?, 0xbc?}, {0x1400000eaf8, 0x1, 0x1})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/row.go:729 +0x374
github.com/segmentio/parquet-go.(*Schema).Reconstruct(0x140000942a0, {0x104ac0ae0?, 0x140001f8e70?}, {0x1400000eaf8, 0x1, 0x1})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/schema.go:264 +0x22c
github.com/segmentio/parquet-go.(*GenericReader[...]).readRows(0x140000ad180, {0x140001f8e70, 0x2, 0x0})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/reader_go18.go:142 +0x148
github.com/segmentio/parquet-go.(*GenericReader[...]).Read(0x104bbe120?, {0x140001f8e70?, 0x0?, 0x51b?})
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/reader_go18.go:107 +0x38
github.com/segmentio/parquet-go_test.TestIssueXXX(0x140000fe340)
        /Users/julienfabre/segment/code/github.com/segmentio/parquet-go/reader_go18_test.go:184 +0x22c
testing.tRunner(0x140000fe340, 0x104bb5af0)
        /usr/local/go/src/testing/testing.go:1446 +0x10c
created by testing.(*T).Run
        /usr/local/go/src/testing/testing.go:1493 +0x300
```

Reproduction:
```
	type B struct {
		Name string
	}
	type A struct {
		B []B `parquet:",optional"`
	}

	b := new(bytes.Buffer)
	w := parquet.NewGenericWriter[A](b)
	expect := []A{
		{
			B: []B{
				{
					Name: "foo",
				},
			},
		},
	}
	_, err := w.Write(expect)
	if err != nil {
		t.Fatal(err)
	}
	if err = w.Close(); err != nil {
		t.Fatal(err)
	}

	bufReader := bytes.NewReader(b.Bytes())
	r := parquet.NewGenericReader[A](bufReader)
	values := make([]A, 2)
	_, err = r.Read(values)
	if err != nil {
		t.Fatal(err)
	}
```
