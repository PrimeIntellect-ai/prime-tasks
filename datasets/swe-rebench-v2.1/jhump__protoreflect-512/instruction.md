nil pointer dereference in linker.go
I was trying to compile the [envoy protobufs](https://github.com/envoyproxy/data-plane-api) using buf-1.3.1 and protoreflect-1.11.1 when the program crashed:

```
$ buf lint
Failure: panic: runtime error: invalid memory address or nil pointer dereference, stack:
goroutine 67 [running]:
runtime/debug.Stack()
	/gnu/store/aiw1716ia4qgwsckcls59sw57dwqr3fg-go-1.17.6/lib/go/src/runtime/debug/stack.go:24 +0x65
github.com/bufbuild/buf/private/bufpkg/bufimage/bufimagebuild.getBuildResults.func1.2()
	/tmp/guix-build-buf-1.3.1.drv-0/source/source/private/bufpkg/bufimage/bufimagebuild/builder.go:158 +0x46
panic({0xd00680, 0x1612040})
	/gnu/store/aiw1716ia4qgwsckcls59sw57dwqr3fg-go-1.17.6/lib/go/src/runtime/panic.go:1038 +0x215
github.com/jhump/protoreflect/desc/protoparse.(*linker).createDescriptorPool(0xc02d703720)
	/tmp/guix-build-buf-1.3.1.drv-0/source/go/pkg/mod/github.com/jhump/protoreflect@v1.11.1-0.20220213155251-0c2aedc66cf4/desc/protoparse/linker.go:149 +0x5dd
github.com/jhump/protoreflect/desc/protoparse.(*linker).linkFiles(0xc02d703720)
	/tmp/guix-build-buf-1.3.1.drv-0/source/go/pkg/mod/github.com/jhump/protoreflect@v1.11.1-0.20220213155251-0c2aedc66cf4/desc/protoparse/linker.go:35 +0x33
github.com/jhump/protoreflect/desc/protoparse.Parser.ParseFiles({{0x0, 0x0, 0x0}, 0x0, 0x0, 0x0, 0xc000d0a048, 0x1, 0x0, 0x0, ...}, ...)
	/tmp/guix-build-buf-1.3.1.drv-0/source/go/pkg/mod/github.com/jhump/protoreflect@v1.11.1-0.20220213155251-0c2aedc66cf4/desc/protoparse/parser.go:232 +0x2f6
github.com/bufbuild/buf/private/bufpkg/bufimage/bufimagebuild.getBuildResult({0xf935f0, 0xc0002e85a0}, {0xf9a0a0, 0xc000d09bc0}, {0xc000d90000, 0x0, 0x9a}, 0x0)
	/tmp/guix-build-buf-1.3.1.drv-0/source/source/private/bufpkg/bufimage/bufimagebuild/builder.go:211 +0x250
github.com/bufbuild/buf/private/bufpkg/bufimage/bufimagebuild.getBuildResults.func1()
	/tmp/guix-build-buf-1.3.1.drv-0/source/source/private/bufpkg/bufimage/bufimagebuild/builder.go:162 +0xd1
created by github.com/bufbuild/buf/private/bufpkg/bufimage/bufimagebuild.getBuildResults
	/tmp/guix-build-buf-1.3.1.drv-0/source/source/private/bufpkg/bufimage/bufimagebuild/builder.go:141 +0x7ba
```

The pertinent line for the stack trace is here: https://github.com/jhump/protoreflect/blob/e5b652849f7f16dfb9db81453ec5d2804266750b/desc/protoparse/linker.go#L149

I'm not sure exacty which value is nil. The envoy protobuf repository is pretty complex so it's probably a bit of an Acid test to handle it.
