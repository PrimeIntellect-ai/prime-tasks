Support unrecognized enum values
It should be possible to support deserialisation of unrecognised enum values without throwing an error so that we handle new enum members gracefully. Like [protocol buffers](https://developers.google.com/protocol-buffers/docs/proto3#enum), the underlying enum value should be left as is.
