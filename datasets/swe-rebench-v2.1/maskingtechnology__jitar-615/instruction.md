Buffer serialization
Currently, buffer objects are serialized using the class serializer. This works, but results into a `depricated` warning because it uses the constructor for the reconstruction. To avoid this warning (and future issues), we need to add a serializer for the buffer that uses the recommended `Buffer.from()` function the constructor.

### Additional contract requirements

The buffer serializer must be registered in the serialization framework built by
`SerializerBuilder.build()`, so that serializing a `Buffer` through that framework
selects the buffer serializer (and not the class serializer or any other serializer).
Concretely, `SerializerBuilder.build().serialize(buffer)` must resolve to the
`SerializedBuffer` shape `{ serialized: true, name: 'Buffer', base64: string }`, and
`SerializerBuilder.build().deserialize(serializedBuffer)` must resolve back to the
original `Buffer`.
