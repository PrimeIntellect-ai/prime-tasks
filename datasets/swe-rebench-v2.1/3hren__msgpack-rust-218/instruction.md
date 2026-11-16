[HIDDEN]
I'm using the `rmpv` crate to serialize some data to MessagePack, some of this data contains dates, so the data needs to be serialized as a Timestamp extension type, with type `-1`. See spec here: https://github.com/msgpack/msgpack/blob/master/spec.md#timestamp-extension-type.

When trying to serialize that data (using `write_value(&mut buf, &Value::Ext(-1, <data_here>)`) the `rmp` crate panics at the following line:
https://github.com/3Hren/msgpack-rust/blob/e96d118/rmp/src/encode/mod.rs#L260

At the moment I'm using a local copy of the crate [HIDDEN], but it would be helpful if [HIDDEN]

### Additional contract requirements

- Serializing an extension value with type `-1` must not panic, and its type byte must be encoded as `0xff`.
