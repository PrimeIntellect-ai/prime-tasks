Panic in mock.Arguments.String
A regression in callString():
```
panic(0x28ff20, 0xdd3bc0)
	/usr/local/go/src/runtime/panic.go:967 +0x166
github.com/stretchr/testify/mock.Arguments.String(0xc000474840, 0x2, 0x2, 0x0, 0x0, 0x0, 0x1, 0x1)
	third-party-source/go/github.com/stretchr/testify/mock/mock.go:833 +0xd1
github.com/stretchr/testify/mock.(*Mock).AssertExpectations(0xc0000a8640, 0x4f7a00, 0xc000199b00, 0x4f3500)
	third-party-source/go/github.com/stretchr/testify/mock/mock.go:464 +0x3b3
```

A proposed fix is coming shortly.

### Additional contract requirements

- For `callString("Method", []interface{}{nil}, false)`, the returned string must be exactly `Method(<nil>)`.
