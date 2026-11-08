Optional.empty() as root object cannot be serialized or deserialized
Following two testcases (added to `OptionalTest`) fail:

````
    @Test
    public void testMarshallEmptyRoot() {
        final Jsonb jsonb = (new JsonBindingBuilder()).build();
        assertEquals("null", jsonb.toJson(Optional.empty()));
    }

    @Test
    public void testUnmarshallEmptyRoot() {
        final Jsonb jsonb = (new JsonBindingBuilder()).build();
        assertEquals(Optional.empty(), jsonb.fromJson("null", new TestTypeToken<Optional<Customer>>() {}.getType()));
    }
````
````
[ERROR] testMarshallEmptyRoot(org.eclipse.yasson.defaultmapping.specific.OptionalTest)  Time elapsed: 0.008 s  <<< ERROR!
javax.json.bind.JsonbException: Internal error: null
        at org.eclipse.yasson/org.eclipse.yasson.internal.Marshaller.marshall(Marshaller.java:81)
        at org.eclipse.yasson/org.eclipse.yasson.internal.Marshaller.marshall(Marshaller.java:101)
        at org.eclipse.yasson/org.eclipse.yasson.internal.JsonBinding.toJson(JsonBinding.java:98)
        at org.eclipse.yasson/org.eclipse.yasson.defaultmapping.specific.OptionalTest.testMarshallEmptyRoot(OptionalTest.java:172)
        ...
Caused by: java.lang.NullPointerException
        at org.eclipse.yasson/org.eclipse.yasson.internal.serializer.OptionalObjectSerializer.serialize(OptionalObjectSerializer.java:82)
        at org.eclipse.yasson/org.eclipse.yasson.internal.serializer.OptionalObjectSerializer.serialize(OptionalObjectSerializer.java:34)
        at org.eclipse.yasson/org.eclipse.yasson.internal.Marshaller.serializeRoot(Marshaller.java:143)
        at org.eclipse.yasson/org.eclipse.yasson.internal.Marshaller.marshall(Marshaller.java:75)
        ... 28 more


javax.json.bind.JsonbException: Error deserialize JSON value into type: class org.eclipse.yasson.defaultmapping.specific.OptionalTest$Customer.
        at org.eclipse.yasson/org.eclipse.yasson.internal.serializer.DeserializerBuilder.build(DeserializerBuilder.java:130)
        at org.eclipse.yasson/org.eclipse.yasson.internal.serializer.OptionalObjectDeserializer.deserialize(OptionalObjectDeserializer.java:35)
        at org.eclipse.yasson/org.eclipse.yasson.internal.serializer.OptionalObjectDeserializer.deserialize(OptionalObjectDeserializer.java:19)
        at org.eclipse.yasson/org.eclipse.yasson.internal.Unmarshaller.deserializeItem(Unmarshaller.java:70)
        at org.eclipse.yasson/org.eclipse.yasson.internal.Unmarshaller.deserialize(Unmarshaller.java:56)
        at org.eclipse.yasson/org.eclipse.yasson.internal.JsonBinding.deserialize(JsonBinding.java:45)
        at org.eclipse.yasson/org.eclipse.yasson.internal.JsonBinding.fromJson(JsonBinding.java:59)
        at org.eclipse.yasson/org.eclipse.yasson.defaultmapping.specific.OptionalTest.testUnmarshallEmptyRoot(OptionalTest.java:178)
````

I see that spec avoids describing mapping of empty optionals except for object properties, but this creates quite uncomfortable asymetry when non-emty ones serialize without issues.

I will provide a PR for these cases.

### Additional contract requirements

The same empty-root handling is required for the primitive optionals:

- Serializing `OptionalInt.empty()`, `OptionalLong.empty()` or `OptionalDouble.empty()` as the root object produces `"null"`.
- Deserializing JSON `null` as `OptionalInt`, `OptionalLong` or `OptionalDouble` produces the corresponding empty optional (`OptionalInt.empty()`, `OptionalLong.empty()`, `OptionalDouble.empty()`).
