Instances of ByteBuffer serialize to empty array
Hi!
I have just encountered an issue when serialising a data class with a `ByteArray` field using avro4k together with kafka-avro-serializer.

The data class I tried to serialize looks like this:
```kotlin
@Serializable
data class File(val content: ByteArray)
```
Here's how I'm serializing it:
```kotlin
Avro.default.toRecord(serializer, data).let { record ->
  return kafkaSerializer.serialize(topic, record)
}
```

The problem is that in the serialized record the array in the `File#content` field is always empty.

I traced back the problem to the way the `ByteBuffer` instances are created in [`ByteArrayEncoder`](https://github.com/sksamuel/avro4k/blob/064a9580e35c1e8ef6ba10ed934e899679e7221a/avro4k-core/src/main/kotlin/com/sksamuel/avro4k/encoder/ByteArrayEncoder.kt#L32).
The created buffers always have the current position set to the index of the last character i.e. `position == limit`.
When serializer attempts to read from such buffers, they appear empty as `ByteBuffer#hasRemaining` will always return `false`.
This in turn results in empty arrays in serialised records.

I think this is a bug as byte buffers created by this library should be ready to be read by consumers of the records.
