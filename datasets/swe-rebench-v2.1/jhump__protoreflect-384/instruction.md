protoparse: allows option allow_alias = true in enums that have no aliases
This is a case where protoparse will accept a proto source file that protoc would reject.

protoc does not allow the use of `option allow_alias = true` in enums unless the values actually include an alias (e.g. two values with same number).

For example:

```proto
// test.proto
syntax = "proto3";
enum Foo {
  option allow_alias = true;
  BAR = 0;
}
```
This yields the following error with protoc:
```
test.proto:7:1: "Foo" declares support for enum aliases but no enum values share field numbers. Please remove the unnecessary 'option allow_alias = true;' declaration.
```
