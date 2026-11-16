What if I don't want the packed serialization?
I'm trying to avoid having a format that inadvertently works. While avoiding serialization is a matter of just not calling the `_packed` functions, deserialization seems to implicitly always use it.

E.g., coding against a spec, I do not want other, incorrect (according to the spec, which might be agnostic to Rust/`serde_cbor`) to successfully deserialize, lest someone thinks that format *is* supported.

### Additional contract requirements

`serde_cbor::Deserializer` provides `disable_packed_format(self) -> Self`. A deserializer configured with this method rejects packed struct representations instead of accepting them; named-field struct representations remain deserializable. The setting applies when deserializing through the returned deserializer.
