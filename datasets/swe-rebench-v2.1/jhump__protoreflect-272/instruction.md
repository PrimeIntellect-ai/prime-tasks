protoparse: index out of range in validateEnum
I've seen a couple of panics in my project (which uses `dynamic` to unmarshal unknown messages). And so have been working on some fuzzing harnesses to try and pin down a small reproducible example. I haven't found my issue yet but did find this index out of range panic in `protoparse`.

Would you be interested in me opening a PR with the basic fuzzing harnesses I've got?
A service like fuzzbuzz.io/fuzzit.dev might be interesting to add to this project to run fuzzing continuously (with a lot more processing power than my laptop...). They're offering free CPU for open source projects and I'd be happy to help integrate it if you want 🙂

Fuzz harness:
```go
package fuzz

import (
	"bytes"
	"github.com/jhump/protoreflect/desc/protoparse"
	"io"
	"io/ioutil"
)

func FuzzParser(data []byte) int {
	files := bytes.Split(data, []byte("\n\n"))
	fileNum := 0

	parser := protoparse.Parser{
		Accessor: func(_ string) (closer io.ReadCloser, e error) {
			if fileNum >= len(files) {
				fileNum = 0
			}

			return ioutil.NopCloser(bytes.NewReader(files[fileNum])), nil
		},
	}

	_, err := parser.ParseFiles("foo")
	if err != nil {
		return 0
	}

	return 1
}
```

Crashing input:
```proto
syntax="proto3";enum o{C}
```

Stack trace:
```
panic: runtime error: index out of range

goroutine 1 [running]:
github.com/jhump/protoreflect/desc/protoparse.validateEnum.func1(0xc00010ec00, 0xc00014aa38)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:1362 +0x6a
github.com/jhump/protoreflect/desc/protoparse.validateEnum(0xc0000713e0, 0xc00014aa01, 0x0, 0x0, 0xc00010ec00, 0xc000071440, 0xc0000b1a68)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:1362 +0x177e
github.com/jhump/protoreflect/desc/protoparse.basicValidate(0xc0000713e0)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:1169 +0x1f2
github.com/jhump/protoreflect/desc/protoparse.parseProto(0x1316269, 0x3, 0x1694308, 0xc000117a60, 0xc00000aca0, 0x1357901, 0xc000071320)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:625 +0x134
github.com/jhump/protoreflect/desc/protoparse.parseProtoFile.func1(0x1358200, 0xc000117a60, 0x1316269, 0x3, 0xc00000aca0, 0x1, 0xc0000b1b88)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:413 +0xe8
github.com/jhump/protoreflect/desc/protoparse.parseProtoFile(0xc0000712c0, 0x1316269, 0x3, 0x0, 0xc00000aca0, 0x101, 0xc0000b1d30)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:414 +0xb06
github.com/jhump/protoreflect/desc/protoparse.parseProtoFiles(0xc0000712c0, 0xc0000b1e60, 0x1, 0x1, 0xc00000aca0, 0x2220101, 0xc0000b1d30)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:392 +0xdb
github.com/jhump/protoreflect/desc/protoparse.Parser.ParseFiles(0x0, 0x0, 0x0, 0x0, 0xc0000712c0, 0x0, 0x0, 0xc0000b1e60, 0x1, 0x1, ...)
	$GOPATH/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:190 +0x202
github.com/jhump/protoreflect/internal/fuzz.FuzzParser(0x2220000, 0x19, 0x200000, 0x4)
	$GOPATH/src/github.com/jhump/protoreflect/internal/fuzz/parser.go:24 +0x203
go-fuzz-dep.Main(0xc0000b1f80, 0x1, 0x1)
	/var/folders/6m/r713l1xj6_dcykbx21svs09h0000gp/T/go-fuzz-build860565645/goroot/src/go-fuzz-dep/main.go:36 +0x1b6
main.main()
	/var/folders/6m/r713l1xj6_dcykbx21svs09h0000gp/T/go-fuzz-build860565645/gopath/src/github.com/jhump/protoreflect/internal/fuzz/go.fuzz.main/main.go:15 +0x52
exit status 2
```

### Additional contract requirements

- Parsing the crashing input `syntax="proto3";enum o{C}` must not panic; it may return a parse or validation error.
- When parsing `enum Foo { }` in `test.proto`, report exactly `test.proto:1:1: enum Foo: enums must define at least one value`.
- For the proto3 error-reporting input where `enum State { C }` precedes `enum Bar { BAZ = 1; BUZZ = 1; }`, report, in order, `test.proto:8:55: enum Bar: proto3 requires that first value in enum have numeric value of 0` and `test.proto:9:56: enum Bar: values BAZ and BUZZ both have the same numeric value 1; use allow_alias option if intentional`, even after reporting the syntax error in `State`.
