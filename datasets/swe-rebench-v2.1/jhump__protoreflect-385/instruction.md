protoparse: does not enforce required message set properties
When a message has message set wire encoding set to true, the message should have no fields and at least one extension range defined. Furthermore, all extensions defined for a message that uses message set encoding must be messages themselves: no scalar extension fields.

These are constraints enforced by protoc, but are not enforced by protoparse. So protoparse will accept an invalid proto source file, that protoc rejects.

### Additional contract requirements

- When reporting these violations, use the exact diagnostics asserted by the tests: `test.proto:1:15: messages with message-set wire format cannot contain non-extension fields` for a message with a non-extension field, `test.proto:1:15: messages with message-set wire format must contain at least one extension range` for a message without an extension range, and `foo.proto:1:99: messages with message-set wire format cannot contain scalar extensions, only messages` for a scalar extension.
