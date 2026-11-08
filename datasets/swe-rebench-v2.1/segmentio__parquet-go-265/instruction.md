Reading of complex structs with []byte fields is incorrect
Hi, we are seeing an issue in our application where sometimes a row contains unexpected data when reading it back with `parquet.Read(<struct>)`.  [Our struct](https://github.com/grafana/tempo/blob/parquet/tempodb/encoding/vparquet/schema.go) contains child structs with several []byte, and it seems like the handling of these is incorrect near page boundaries.

Was able to create a minimal reproduction test below.   It writes 2 very small objects with 1 child byte slice.  When reading row 0 it contains the child from row 1.  An observation:  This only occurs when using `writer.Write(<struct>)` and seems ok when using `parquet.Buffer`.  Unsure if there is a fundamental difference or just needs different conditions.

```go
func TestRoundtripNestedRepeatedBytes(t *testing.T) {
	type B struct {
		C []byte
	}
	type A struct {
		A string
		B []B
	}

	var objs []A
	for i := 0; i < 2; i++ {
		o := A{
			"test" + strconv.Itoa(i),
			[]B{
				{[]byte{byte(i)}},
			},
		}
		objs = append(objs, o)
	}

	buf := new(bytes.Buffer)
	w := parquet.NewWriter(buf, parquet.PageBufferSize(100))
	for _, o := range objs {
		w.Write(&o)
	}
	w.Close()

	file := bytes.NewReader(buf.Bytes())

	r := parquet.NewReader(file)
	for i := 0; ; i++ {
		o := new(A)
		err := r.Read(o)
		if errors.Is(err, io.EOF) {
			if i < len(objs) {
				t.Errorf("too few rows were read: %d<%d", i, len(objs))
			}
			break
		}
		[HIDDEN]
			t.Errorf("points mismatch at row index %d: want=%v got=%v", i, objs[i], o)
		}
	}
}
```

```
parquet-go $ go test -v -run=TestRoundtripNestedRepeatedBytes
=== RUN   TestRoundtripNestedRepeatedBytes
    buffer_test.go:526: points mismatch at row index 0: want={test0 [{[0]}]} got=&{test0 [{[1]}]}
--- FAIL: TestRoundtripNestedRepeatedBytes (0.00s)
```

Output from `parquet-tools dump <file>`
```
row group 0
--------------------------------------------------------------------------------
A:   BINARY UNCOMPRESSED DO:0 FPO:4 SZ:60/60/1.00 VC:2 ENC:DELTA_LENGTH_BYTE_ARRAY ST:[no stats for this column]
B:
.C:  BINARY UNCOMPRESSED DO:0 FPO:64 SZ:76/76/1.00 VC:2 ENC:RLE,DELTA_LENGTH_BYTE_ARRAY ST:[no stats for this column]

    A TV=2 RL=0 DL=0
    ----------------------------------------------------------------------------
    page 0:  DLE:RLE RLE:RLE VLE:DELTA_LENGTH_BYTE_ARRAY ST:[no stats for this column] SZ:32 VC:2

    B.C TV=2 RL=1 DL=1
    ----------------------------------------------------------------------------
    page 0:  DLE:RLE RLE:RLE VLE:DELTA_LENGTH_BYTE_ARRAY ST:[no stats for this column] SZ:10 VC:1
    page 1:  DLE:RLE RLE:RLE VLE:DELTA_LENGTH_BYTE_ARRAY ST:[no stats for this column] SZ:10 VC:1

BINARY A
--------------------------------------------------------------------------------
*** row group 1 of 1, values 1 to 2 ***
value 1: R:0 D:0 V:test0
value 2: R:0 D:0 V:test1

BINARY B.C
--------------------------------------------------------------------------------
*** row group 1 of 1, values 1 to 2 ***
value 1: R:0 D:1 V:0x00
value 2: R:0 D:1 V:0x01
```

### Additional contract requirements

- Reading rows written from structs with nested repeated `[]byte` fields must preserve the bytes belonging to each row rather than returning another row’s bytes.
