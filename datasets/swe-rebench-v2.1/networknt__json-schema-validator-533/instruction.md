Invalid (non-string) $schema produces NullPointerException
The following code produces a `NullPointerException`:

```java
JsonSchemaFactory factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V7);
factory.getSchema("{ \"$schema\": true }");
```

The `$schema` property should be a string but there is no check that it is, in fact, a string.

Note that I have a fix for this I will put up in a PR shortly.

### Additional contract requirements

- For the input shown above, `factory.getSchema("{ \"$schema\": true }")` must throw a `JsonSchemaException` with the exact message `Unknown MetaSchema: true`.
