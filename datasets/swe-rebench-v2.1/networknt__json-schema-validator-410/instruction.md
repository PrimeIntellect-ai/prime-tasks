Behavior change of $ref resolution
In our system we support some well known URNs that our clients can use in their schema definitions, using the `$ref` keyword, for example:

```
{
    "properties": {
        "someField": {
            "$ref": "urn:my-company:my-custom-type"
        }
    }
}
```

We use a custom `URNFactory` and works great.

But we have observed the way of the URN resolution has changed as of release `1.0.49`. Previously, if a schema contained an unknown URN the call to `JsonSchemaFactory.getSchema(...)` failed with a `JsonSchemaException`. Now it does not fail in that moment but later, when calling to `JsonSchema.validate(...)`. I suspect this change could be due to https://github.com/networknt/json-schema-validator/pull/377.

Is is possible to recover the old behavior and resolve the `$ref` keywords when getting the schema? that way we would ensure the schema instantiated is valid, or at least would it be possible to provide a way to load the `$ref` schemas eagerly after getting the schema instance?

### Additional contract requirements

Schema references must be resolvable before validation. An unresolved URN reference must cause a `JsonSchemaException` either while the schema is obtained or when eager resolution is explicitly requested. When eager resolution is deferred, callers can request it using `JsonSchema.initializeValidators()`. This eager resolution must include references nested in subschemas, including schemas under `properties`.
