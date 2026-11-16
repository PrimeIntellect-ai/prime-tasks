NullPointerException at com.networknt.schema.JsonSchema.combineCurrentUriWithIds(JsonSchema.java:90)
Here is my code:

```groovy
    def jsonSchema = this.getClass().getClassLoader().getResource("schema/test.json").text
    JsonSchemaFactory factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V7)
    JsonSchema schema = factory.getSchema(jsonSchema)
```

If the schema's `$id` field does not start with a scheme, it will throw a null pointer exception. Here is the full stack trace:

```
java.lang.NullPointerException
	at com.networknt.schema.JsonSchema.combineCurrentUriWithIds(JsonSchema.java:90)
	at com.networknt.schema.JsonSchema.<init>(JsonSchema.java:72)
	at com.networknt.schema.JsonSchema.<init>(JsonSchema.java:58)
	at com.networknt.schema.JsonSchema.<init>(JsonSchema.java:53)
	at com.networknt.schema.JsonSchemaFactory.newJsonSchema(JsonSchemaFactory.java:254)
	at com.networknt.schema.JsonSchemaFactory.getSchema(JsonSchemaFactory.java:282)
	at com.networknt.schema.JsonSchemaFactory.getSchema(JsonSchemaFactory.java:290)
```

Here is my test schema:

```json
{
  "$id": "test",
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Test description",
  "properties": {
    "test": {
      "description": "Sample property",
      "examples": [
        "hello",
        "world"
      ],
      "type": "string"
    }
  },
  "required": [
    "test"
  ],
  "type": "object"
}
```

It should throw a `JsonSchemaException` instead of a `NullPointerException`, but [HIDDEN]

### Additional contract requirements

- For this case, the `JsonSchemaException` message must be exactly `test: null is an invalid segment for URI {2}`.
