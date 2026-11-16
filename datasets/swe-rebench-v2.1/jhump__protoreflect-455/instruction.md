protoparse: ParseFiles doesn't catch duplicate oneof names
ParseFiles does not oneof names for duplicates.

```protobuf
syntax = "proto3";
message m{
  oneof z{
    int64 z=1;
  }
}

// protoc error:
// a.proto:4:11: "z" is already defined in "m".

```

```proto
syntax="proto3";
message m{
  string z = 1;
  oneof z{int64 b=2;}
}

// protoc error:
// a.proto:3:10: "z" is already defined in "m".

```

```proto
syntax="proto3";
message m{
  oneof z{int64 a=1;}
  oneof z{int64 b=2;}
}

// protoc error:
// a.proto: "z" is already defined in "m".

```

### Additional contract requirements

- For these cases, ParseFiles must report these exact diagnostics: when a field named `z` is inside oneof `z`, `a.proto:4:5: duplicate symbol m.z: already defined as oneof`; when message field `z` and oneof `z` have the same name, `a.proto:3:3: duplicate symbol m.z: already defined as oneof`; and when a message has two oneofs named `z`, `a.proto:4:3: duplicate symbol m.z: already defined as oneof`.
