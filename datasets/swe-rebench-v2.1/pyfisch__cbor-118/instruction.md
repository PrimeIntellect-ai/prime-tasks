Change enum serialization
https://serde.rs/enum-representations.html

Serde CBOR should use the "Externally tagged" format by default in the next breaking version.
Also make sure that the other formats round-trip.
The current array based serialization should be kept as a legacy format so old data can be read.

### Additional contract requirements

- With the default externally tagged representation, unit, newtype, tuple, and struct enum variants must round-trip through serialization and deserialization, preserving the variant and its payload.
- Deserialization must also accept enum values in the existing legacy array-based representation. Callers must be able to opt into emitting that representation with `Serializer::legacy_enums(self) -> Serializer<W>`, without changing the serializer’s other settings.
