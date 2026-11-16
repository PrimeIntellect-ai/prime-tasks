Decoding fails when missing map in reader class
**Describe the bug**
[HIDDEN] [HIDDEN]

I encountered this error after evolving a schema in the producer and Schema Registry, adding a new field of type map (with empty default value)

[HIDDEN]

**Stack trace**
```
Caused by: org.apache.avro.AvroRuntimeException: Not an array: {"type":"map","values" ... not pasting the full schema }
	at org.apache.avro.Schema.getElementType(Schema.java:374)
	at com.github.avrokotlin.avro4k.internal.decoder.direct.RecordDirectDecoderKt.skip(RecordDirectDecoder.kt:204)
	at com.github.avrokotlin.avro4k.internal.decoder.direct.RecordDirectDecoderKt.access$skip(RecordDirectDecoder.kt:1)
	at com.github.avrokotlin.avro4k.internal.decoder.direct.RecordDirectDecoder.decodeElementIndex(RecordDirectDecoder.kt:42)
```

**To Reproduce**
I could not replicate the behavior in unit tests yet because mapBlockItems is always equal to zero when I try, however, I can outline the steps that led to the failure in all the environments I tested the library:
- Evolve an Avro schema in the producer and Schema Registry by adding a new map field, using an empty map `{}` as the default value.
- Produce a message using the evolved schema.
- Same error should be triggered

If I manage to reproduce it in a test, I'll add an update in a new comment


**Expected behavior**
The map type is skipped correctly

**Desktop:**
- Kotlin version: 2.1.10
- Avro4k version: 2.2.0
- Other kotlinx-version: 1.8.0

### Additional contract requirements

- When decoding a writer-side map field that is absent from the reader, skip the map correctly so decoding can continue.
