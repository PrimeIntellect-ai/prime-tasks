Cannot marshal map which key is defined type
```go
type keyType string
type A struct {
	Field map[keyType]string `yaml:"field"`
}

a := A{
	Field: map[keyType]string{
		keyType("hello"): "world",
	},
}
data, err := yaml.Marshal(&a)
if err != nil {
	fmt.Printf("%+v", err)
	os.Exit(1)
}
fmt.Println(string(data))
```

expect:

```
field:
  hello: world
```

got:

```
panic: interface conversion: interface {} is main.keyType, not string

goroutine 1 [running]:
github.com/goccy/go-yaml.(*Encoder).encodeMap(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x111c840, 0xc0000b0018, 0x195, 0x1, 0x110e59f, 0x5)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:428 +0x8aa
github.com/goccy/go-yaml.(*Encoder).encodeValue(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x111c840, 0xc0000b0018, 0x195, 0x1, 0x195, 0x0, 0xc0000ac038, ...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:295 +0xb88
github.com/goccy/go-yaml.(*Encoder).encodeStruct(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x1120480, 0xc0000b0018, 0x199, 0x1, 0x401, 0x0, 0xc000092c58, ...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:543 +0x492
github.com/goccy/go-yaml.(*Encoder).encodeValue(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x1120480, 0xc0000b0018, 0x199, 0x1, 0x0, 0x64, 0x17311a0, ...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:293 +0xd05
github.com/goccy/go-yaml.(*Encoder).encodeValue(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x1112360, 0xc0000b0018, 0x16, 0x1, 0x1132700, 0xc0000ba000, 0x80, ...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:270 +0xae5
github.com/goccy/go-yaml.(*Encoder).EncodeToNodeContext(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x1112360, 0xc0000b0018, 0xc000092e01, 0xc000098420, 0xc000092e00, 0x100e22d)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:100 +0x1c5
github.com/goccy/go-yaml.(*Encoder).EncodeContext(0xc0000ba000, 0x1169078, 0xc0000ac008, 0x1112360, 0xc0000b0018, 0x110, 0x12955b8)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/encode.go:79 +0x5d
github.com/goccy/go-yaml.MarshalWithContext(0x1169078, 0xc0000ac008, 0x1112360, 0xc0000b0018, 0x0, 0x0, 0x0, 0x8baba9a6675c172d, 0xc000092ed8, 0x100e22d, ...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/yaml.go:139 +0x11b
github.com/goccy/go-yaml.MarshalWithOptions(...)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/yaml.go:133
github.com/goccy/go-yaml.Marshal(0x1112360, 0xc0000b0018, 0x113c15e, 0x5, 0xc0000b8088, 0xc00008c000, 0xc00003e748)
	/Users/ryo.kitagawa/go/pkg/mod/github.com/goccy/go-yaml@v1.8.9/yaml.go:128 +0x65
main.main()
	/Users/ryo.kitagawa/go/src/github.com/kitagry/go-yaml-example/main.go:21 +0xcb
exit status 2
```
