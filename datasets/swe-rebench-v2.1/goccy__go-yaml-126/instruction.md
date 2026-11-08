Two levels of inline depth results in reflection error
Hey @goccy,

I've added the following test:
```go
func TestDecoder_InlineDoubleBase(t *testing.T) {
	type Base struct {
		A int
		B string
	}
	yml := `---
a: 1
b: hello
`
	type Base2 struct {
		Base *Base `yaml:",inline"`
	}
	var v struct {
		Base2 *Base2 `yaml:",inline"`
	}
	if err := yaml.NewDecoder(strings.NewReader(yml), yaml.Strict()).Decode(&v); err != nil {
		t.Fatalf("%+v", err)
	}
	if v.Base2.Base.A != 1 {
		t.Fatal("failed to decode with inline key")
	}
	if v.Base2.Base.B != "hello" {
		t.Fatal("failed to decode with inline key")
	}
}
```

the test resulted in the following reflect panic
```
--- FAIL: TestDecoder_InlineDoubleTest (0.00s)
panic: reflect: call of reflect.Value.FieldByName on ptr Value [recovered]
        panic: reflect: call of reflect.Value.FieldByName on ptr Value

goroutine 27 [running]:
testing.tRunner.func1.1(0x12099c0, 0xc00032c920)
        /usr/local/Cellar/go/1.14/libexec/src/testing/testing.go:941 +0x3d0
testing.tRunner.func1(0xc0003306c0)
        /usr/local/Cellar/go/1.14/libexec/src/testing/testing.go:944 +0x3f9
panic(0x12099c0, 0xc00032c920)
        /usr/local/Cellar/go/1.14/libexec/src/runtime/panic.go:967 +0x15d
reflect.flag.mustBe(...)
        /usr/local/Cellar/go/1.14/libexec/src/reflect/value.go:208
reflect.Value.FieldByName(0x11efee0, 0xc0002c5bc8, 0x196, 0x11e87a4, 0x4, 0x11eff01, 0x11e87aa, 0xe)
        /usr/local/Cellar/go/1.14/libexec/src/reflect/value.go:880 +0x1ed
github.com/goccy/go-yaml.(*Decoder).deleteStructKeys(0xc0003034a0, 0x11efee0, 0xc0002c5bc8, 0x196, 0xc0003343c0, 0x12153e0, 0xc0002c5c20)
        /Users/user/work/go-yaml/decode.go:386 +0x238
github.com/goccy/go-yaml.(*Decoder).decodeStruct(0xc0003034a0, 0x1211da0, 0xc0002c5bc8, 0x199, 0x12ae720, 0xc000320d00, 0x28, 0x121d6c0)
        /Users/user/work/go-yaml/decode.go:788 +0xde7
github.com/goccy/go-yaml.(*Decoder).decodeValue(0xc0003034a0, 0x1211da0, 0xc0002c5bc8, 0x199, 0x12ae720, 0xc000320d00, 0x0, 0x12)
        /Users/user/work/go-yaml/decode.go:474 +0x1b0a
github.com/goccy/go-yaml.(*Decoder).decode(0xc0003034a0, 0x11f5460, 0xc0002c5bc8, 0x16, 0x11f5460, 0x1415800)
        /Users/user/work/go-yaml/decode.go:1244 +0xd2
github.com/goccy/go-yaml.(*Decoder).Decode(0xc0003034a0, 0x11f5460, 0xc0002c5bc8, 0x10565f9, 0x7380299ca20cb)
        /Users/user/work/go-yaml/decode.go:1273 +0x272
github.com/goccy/go-yaml_test.TestDecoder_Inline(0xc0003306c0)
        /Users/user/work/go-yaml/decode_test.go:1315 +0x1da
testing.tRunner(0xc0003306c0, 0x125f6f0)
        /usr/local/Cellar/go/1.14/libexec/src/testing/testing.go:992 +0xdc
created by testing.(*T).Run
        /usr/local/Cellar/go/1.14/libexec/src/testing/testing.go:1043 +0x357
FAIL    github.com/goccy/go-yaml        0.519s
FAIL

```
