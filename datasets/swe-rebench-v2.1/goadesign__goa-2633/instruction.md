v3.2.0: stack overflow on OpenAPI3 generator when used recursive UserType.
It caused a stack overflow when I defined this DSL and executed `goa gen`.

DSL:
```go
var recursiveUserType = Type("recursiveUserType", func() {
	Attribute("children", ArrayOf("recursiveUserType"))
})

var arrResultType = ResultType("recursiveArrayResultType", func() {
	Attribute("result", recursiveUserType)
})

var _ = Service(svc, func() {
	Method(met, func() {
		Result(arrResultType)
		HTTP(func() {
			GET("/")
		})
	})
})
```

Trace:
```
runtime: goroutine stack exceeds 1000000000-byte limit
runtime: sp=0xc020460338 stack=[0xc020460000, 0xc040460000]
fatal error: stack overflow

runtime stack:
runtime.throw(0xa48cf0, 0xe)
	/home/pyyoshi/.gopath/src/runtime/panic.go:1116 +0x72
runtime.newstack()
	/home/pyyoshi/.gopath/src/runtime/stack.go:1034 +0x6ce
runtime.morestack()
	/home/pyyoshi/.gopath/src/runtime/asm_amd64.s:449 +0x8f

goroutine 58 [running]:
runtime.heapBitsSetType(0xc0014a4400, 0x10, 0x10, 0x95faa0)
	/home/pyyoshi/.gopath/src/runtime/mbitmap.go:947 +0xa4d fp=0xc020460348 sp=0xc020460340 pc=0x41811d
runtime.mallocgc(0x10, 0x95faa0, 0x1, 0x0)
	/home/pyyoshi/.gopath/src/runtime/malloc.go:1066 +0x53e fp=0xc0204603e8 sp=0xc020460348 pc=0x40e17e
runtime.makeslice(0x95faa0, 0x1, 0x1, 0x0)
	/home/pyyoshi/.gopath/src/runtime/slice.go:49 +0x6c fp=0xc020460418 sp=0xc0204603e8 pc=0x44d9ec
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:334 +0xbe fp=0xc0204604d0 sp=0xc020460418 pc=0x8a9bfe
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c6e0, 0xb33ca0, 0xc00030b5d8, 0xc00030b5d8)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:373 +0x62b fp=0xc020460588 sp=0xc0204604d0 pc=0x8aa16b
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c630, 0xb33ca0, 0xc00030b5d8, 0xc00042c630)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:357 +0x427 fp=0xc020460640 sp=0xc020460588 pc=0x8a9f67
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:342 +0x239 fp=0xc0204606f8 sp=0xc020460640 pc=0x8a9d79
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c6e0, 0xb33ca0, 0xc00030b5d8, 0xc00030b5d8)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:373 +0x62b fp=0xc0204607b0 sp=0xc0204606f8 pc=0x8aa16b
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c630, 0xb33ca0, 0xc00030b5d8, 0xc00042c630)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:357 +0x427 fp=0xc020460868 sp=0xc0204607b0 pc=0x8a9f67
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:342 +0x239 fp=0xc020460920 sp=0xc020460868 pc=0x8a9d79
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c6e0, 0xb33ca0, 0xc00030b5d8, 0xc00030b5d8)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:373 +0x62b fp=0xc0204609d8 sp=0xc020460920 pc=0x8aa16b
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c630, 0xb33ca0, 0xc00030b5d8, 0xc00042c630)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:357 +0x427 fp=0xc020460a90 sp=0xc0204609d8 pc=0x8a9f67
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:342 +0x239 fp=0xc020460b48 sp=0xc020460a90 pc=0x8a9d79
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c6e0, 0xb33ca0, 0xc00030b5d8, 0xc00030b5d8)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:373 +0x62b fp=0xc020460c00 sp=0xc020460b48 pc=0x8aa16b
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c630, 0xb33ca0, 0xc00030b5d8, 0xc00042c630)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:357 +0x427 fp=0xc020460cb8 sp=0xc020460c00 pc=0x8a9f67
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:342 +0x239 fp=0xc020460d70 sp=0xc020460cb8 pc=0x8a9d79
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c6e0, 0xb33ca0, 0xc00030b5d8, 0xc00030b5d8)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:373 +0x62b fp=0xc020460e28 sp=0xc020460d70 pc=0x8aa16b
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c630, 0xb33ca0, 0xc00030b5d8, 0xc00042c630)
	/home/pyyoshi/.gopath/src/goa.design/goa/v3/http/codegen/openapi/v3/types.go:357 +0x427 fp=0xc020460ee0 sp=0xc020460e28 pc=0x8a9f67
goa.design/goa/v3/http/codegen/openapi/v3.hashAttribute(0xc00042c580, 0xb33ca0, 0xc00030b5d8, 0xb38080)

...

```

---

Please excuse me for my poor English.
