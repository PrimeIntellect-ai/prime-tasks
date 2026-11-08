protoparse: numbers starting with 0 should be octal
According to protoc "Numbers starting with leading zero must be in octal". The [spec seems to agree](https://developers.google.com/protocol-buffers/docs/reference/proto3-spec#integer_literals):

```
intLit     = decimalLit | octalLit | hexLit
decimalLit = ( "1" … "9" ) { decimalDigit }
octalLit   = "0" { octalDigit }
hexLit     = "0" ( "x" | "X" ) hexDigit { hexDigit }
```

example:

```protobuf
message o {
  optional bool f=09;
}

// protoc error:
// a.proto:2:26: Numbers starting with leading zero must be in octal.
// a.proto:2:25: Integer out of range.
```

### Additional contract requirements

- When lexing `09`, report `invalid syntax in octal integer value: 09`; when lexing `0f`, report `invalid syntax in octal integer value: 0f`.
