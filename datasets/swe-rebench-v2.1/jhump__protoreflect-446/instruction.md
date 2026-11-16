protoparse: ParseFiles allows reserved and extensions to have 0 value
`protoc` requires that field numbers for `reserved` and `extensions` be positive integers, but protoparse allows 0 values.

```protobuf
syntax = "proto3";
message t{
  reserved 0 to 10;
}
```

protoc result:
```
0.proto: Reserved numbers must be positive integers.
```

```protobuf
syntax = "proto2";
message t{
  extensions 0 to 10;
}
```

protoc result:
```
0.proto:3:14: Extension numbers must be positive integers.
```

### Additional contract requirements

- When these range validations fail, the diagnostic must match the expected text exactly: `test.proto:1:24: range start 0 is out of range: should be between 1 and 536870911`; `test.proto:1:26: range start 0 is out of range: should be between 1 and 536870911`; `test.proto:1:29: range end 5000000000 is out of range: should be between 1 and 536870911`; `test.proto:1:26: range start 3000000000 is out of range: should be between 1 and 536870911`; and `test.proto:1:33: range end 3000000000 is out of range: should be between 1 and 536870911`.
