Custom error serialization broken in 1.4.0
I added `registerClass` in Blitz internals so that blitz custom errors are fully deserialized on the client to work with `instanceof`. This works great in 1.3.0, but breaks in 1.4.0.

In 1.4.0, the custom error is serialized as a plain Error instead of the custom error class.

Also, I noticed that in 1.4.0 extra static properties on the error are not serialized. In 1.3.0 blitz errors have `statusCode` properly serialized, but in `1.4.0` they don't.

Related Blitz PR: https://github.com/blitz-js/blitz/pull/1414

### Additional contract requirements

- The extra properties referred to above are properties carried by the error value itself (for example a `statusCode` field); they are preserved through serialization and deserialization.
