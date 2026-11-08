Panic `index out of range` when use `Reset` with multiple row groups
### Minimal test example

```golang
func TestResetWithRowGroups(t *testing.T) {
	type testStruct struct {
		A int `parquet:"a,plain"`
	}

	tests := make([]testStruct, 100)
	for i := range 100 {
		tests[i] = testStruct{A: i + 1}
	}

	b := bytes.NewBuffer(nil)
	w := parquet.NewGenericWriter[testStruct](b, parquet.MaxRowsPerRowGroup(10))
	_, _ = w.Write(tests[0:50])
	_ = w.Close()

	b = bytes.NewBuffer(nil)
	w.Reset(b)
	_, _ = w.Write(tests[50:100])
	_ = w.Close()
}
```

### Expected

No panic

### Actual

```
--- FAIL: TestResetWithRowGroups (0.00s)
panic: runtime error: index out of range [1] with length 1 [recovered]
        panic: runtime error: index out of range [1] with length 1

goroutine 3501 [running]:
testing.tRunner.func1.2({0x1086fc0, 0xc0003e6c00})
        testing/testing.go:1631 +0x3f7
testing.tRunner.func1()
        testing/testing.go:1634 +0x6b6
panic({0x1086fc0?, 0xc0003e6c00?})
        runtime/panic.go:770 +0x132
github.com/parquet-go/parquet-go.(*writer).writeFileFooter(0xc0006fbc80)
        github.com/parquet-go/parquet-go/writer.go:868 +0x1566
github.com/parquet-go/parquet-go.(*writer).close(0xc0006fbc80)
        github.com/parquet-go/parquet-go/writer.go:815 +0x129
github.com/parquet-go/parquet-go.(*Writer).Close(...)
        github.com/parquet-go/parquet-go/writer.go:364
github.com/parquet-go/parquet-go.(*GenericWriter[...]).Close(0x125b380)
        github.com/parquet-go/parquet-go/writer.go:178 +0x11d
github.com/parquet-go/parquet-go_test.TestResetWithRowGroups(0xc000168680?)
        github.com/parquet-go/parquet-go/writer_test.go:1650 +0x2bd
testing.tRunner(0xc000168680, 0x11155c8)
        testing/testing.go:1689 +0x21f
created by testing.(*T).Run in goroutine 1
        testing/testing.go:1742 +0x826
FAIL    github.com/parquet-go/parquet-go        96.351s
```
