Add msgpack specific exception types
### Unpacker

InvalidSequence -- it's not msgpack.
NestLimitExceeded -- too nested.

any more ?

### Packer

any?

### Additional contract requirements

- `msgpack.exceptions` defines the public exception classes `FormatError` and `StackError`; both are importable from the top-level `msgpack` package.
- For Unpacker errors, the public exception names are `FormatError` for invalid MsgPack and `StackError` for excessive nesting; the names in the base text describe those conditions, not additional required exception classes.
- `unpackb` raises `FormatError` when the input is not valid MsgPack, including unknown type tags and malformed structures.
- `unpackb` raises `StackError` when the input is nested more than 1024 levels deep.
