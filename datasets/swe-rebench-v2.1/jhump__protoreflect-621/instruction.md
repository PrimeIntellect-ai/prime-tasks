ParseFilesButDoNotLink panics in option validation with invalid .proto
Feel free to tell me that I’m holding it wrong, but I figured I’d report this issue.

We have a pipeline with which we analyze all .proto files in our repo. The pipeline parses proto files using the `InterpretOptionsInUnlinkedFiles` and `IncludeSourceCodeInfo` options, so that we can work with some custom options we’re using.

I noticed that the pipeline panic'd when processing a specific .proto file, but that behavior only started happening recently.

I distilled it down into the following test case:

```go
func TestOptionsValidation(t *testing.T) {
	testCases := []struct {
		contents string
		succeeds bool
		errMsg   string
	}{
		{
			contents: `syntax = "proto2";
package foo;
option malformed_non_existant = true;
option features.utf8_validation = NONE;
`,
			errMsg: `bleh`,
		},
	}

	for i, tc := range testCases {
		_, err := Parser{
			Accessor: FileContentsFromMap(map[string]string{"test.proto": tc.contents}),
			//ValidateUnlinkedFiles:           true,
			InterpretOptionsInUnlinkedFiles: true,
			IncludeSourceCodeInfo:           true,
		}.ParseFilesButDoNotLink("test.proto")
		if tc.succeeds {
			testutil.Ok(t, err, "case #%d should succeed", i)
		} else {
			testutil.Nok(t, err, "case #%d should fail", i)
			testutil.Eq(t, tc.errMsg, err.Error(), "case #%d bad error message", i)
		}
	}
}
```

…which panics with the following backtrace:

```
go test -run=OptionsVal
--- FAIL: TestOptionsValidation (0.00s)
panic: runtime error: invalid memory address or nil pointer dereference [recovered]
	panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x7525ec]

goroutine 6 [running]:
testing.tRunner.func1.2({0xa4a540, 0x107f7a0})
	/usr/lib/go-1.22/src/testing/testing.go:1631 +0x24a
testing.tRunner.func1()
	/usr/lib/go-1.22/src/testing/testing.go:1634 +0x377
panic({0xa4a540?, 0x107f7a0?})
	/usr/lib/go-1.22/src/runtime/panic.go:770 +0x132
github.com/bufbuild/protocompile/options.findOptionNode[...].func1({0xc11430, 0xc000013c68})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:994 +0x6c
github.com/bufbuild/protocompile/options.(*optionsRanger).Range.optionsRanger.Range.func1(0x10?)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:1018 +0x1f
github.com/bufbuild/protocompile/ast.(*FileNode).RangeOptions(0x413fc5?, 0xc000362d50)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/ast/file.go:142 +0x58
github.com/bufbuild/protocompile/options.optionsRanger.Range(...)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:1017
github.com/bufbuild/protocompile/options.findOptionNode[...]({0xc0003809a8, 0x2, 0x2}, {0xc0cce0, 0xc000362d20}, 0xc000362d30)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:992 +0x103
github.com/bufbuild/protocompile/options.(*interpreter).findOptionNode(0xc00032c6c0, {0xc0003809a8, 0x2, 0x2}, {0xc0c3a0?, 0xc000328600?})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:970 +0x116
github.com/bufbuild/protocompile/options.(*interpreter).validateFeatureSupport(0xc00032c6c0, 0x0, 0xc0003a6690, {0xb183fd, 0x5}, {0xc0001504e4, 0x2a}, {0xc0003809a8, 0x2, 0x2}, ...)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:937 +0x9c
github.com/bufbuild/protocompile/options.(*interpreter).validateRecursive.func1({0xc21788, 0xc0001448f0}, {{}, 0xa0cb80?, 0x0?, 0xa0bec0?})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:831 +0x6d6
google.golang.org/protobuf/internal/impl.(*messageState).Range(0xc00032c840, 0xc00032c900)
	/home/stapelberg/go/pkg/mod/google.golang.org/protobuf@v1.34.2-0.20240529085009-ca837e5c658b/internal/impl/message_reflect_gen.go:51 +0x1e3
github.com/bufbuild/protocompile/options.(*interpreter).validateRecursive(0xc00032c6c0, 0x0, {0xc1d810, 0xc00032c840}, {0xc0003809b0, 0x9}, {0xc0c3a0, 0xc000328600}, {0xc0003809a8, 0x1, ...}, ...)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:799 +0x1cc
github.com/bufbuild/protocompile/options.(*interpreter).validateRecursive.func1({0xc21788, 0xc000147270}, {{}, 0xafa3a0?, 0xc00032c840?, 0x0?})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:900 +0xca5
google.golang.org/protobuf/internal/impl.(*messageState).Range(0xc0002a85a0, 0xc00032c8a0)
	/home/stapelberg/go/pkg/mod/google.golang.org/protobuf@v1.34.2-0.20240529085009-ca837e5c658b/internal/impl/message_reflect_gen.go:51 +0x1e3
github.com/bufbuild/protocompile/options.(*interpreter).validateRecursive(0xc00032c6c0, 0x0, {0xc1d810, 0xc0002a85a0}, {0x0, 0x0}, {0xc0c3a0, 0xc000328600}, {0x0, 0x0, ...}, ...)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:799 +0x1cc
github.com/bufbuild/protocompile/options.(*interpreter).interpretOptions(0xc00032c6c0, {0xb1cebe, 0xa}, 0x1, {0xc0c3a0, 0xc000328600}, {0xc0c3e0, 0xc0002a82d0}, {0xc000094818, 0x1, ...}, ...)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:653 +0xaa5
github.com/bufbuild/protocompile/options.interpretElementOptions[...](0xc00032c6c0, {0xb1cebe, 0xa}, 0x1083c00, 0xc000328600, 0x1)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:538 +0x3e5
github.com/bufbuild/protocompile/options.(*interpreter).interpretFileOptions(0xc00032c6c0, {0xc1de48?, 0xc0003628e0?}, 0x1)
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:159 +0xf2
github.com/bufbuild/protocompile/options.interpretOptions(0x1, {0xc1de48, 0xc0003628e0}, {0x0, 0x0}, 0xc0003844c0, {0x0, 0x0, 0x0?})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:147 +0x1f0
github.com/bufbuild/protocompile/options.InterpretUnlinkedOptions({0xc1db10?, 0xc0000b11c0?}, {0x0, 0x0, 0x0})
	/home/stapelberg/go/pkg/mod/github.com/bufbuild/protocompile@v0.14.0/options/options.go:125 +0xfe
github.com/jhump/protoreflect/desc/protoparse.Parser.ParseFilesButDoNotLink({{0x0, 0x0, 0x0}, 0x0, 0x0, 0x0, 0xc000362750, 0x1, 0x0, 0x1, ...}, ...)
	/home/stapelberg/go/src/github.com/jhump/protoreflect/desc/protoparse/parser.go:281 +0x3bb
github.com/jhump/protoreflect/desc/protoparse.TestOptionsValidation(0xc0000fdba0)
	/home/stapelberg/go/src/github.com/jhump/protoreflect/desc/protoparse/validate_test.go:437 +0x228
testing.tRunner(0xc0000fdba0, 0xb697b0)
	/usr/lib/go-1.22/src/testing/testing.go:1689 +0xfb
created by testing.(*T).Run in goroutine 1
	/usr/lib/go-1.22/src/testing/testing.go:1742 +0x390
exit status 2
FAIL	github.com/jhump/protoreflect/desc/protoparse	0.045s

```

Notably, it works with github.com/bufbuild/protocompile v0.13.0, but panics only when I `go get github.com/bufbuild/protocompile@v0.14.0`.

Also, the panic disappears when I additionally enable `ValidateUnlinkedFiles`, presumably because execution doesn’t get as far anymore in that case.

Is it expected that we need to enable `ValidateUnlinkedFiles` in order for option interpretation to work, or is this a regression?

Thanks

### Additional contract requirements

- For the supplied input and parser options, parsing must return an error whose `Error()` string is exactly `test.proto:4:33: field "google.protobuf.FeatureSet.utf8_validation" was not introduced until edition 2023`.
