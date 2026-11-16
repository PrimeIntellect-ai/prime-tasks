`Field.MarshalJSON` doesn't correctly encode null default values in unions
Hello, first thank you for writing and supporting this library!

As the title says, there is an issue when json encoding a schema containing unions with a default null value. For example a schema defined like this:

```json
{
    "type":"record",
    "namespace": "org.hamba.avro",
    "name":"X",
    "fields":[{"name":"value", "type": ["null", "int"], "default": null}]
}
```

When json marshalled, it becomes:

```json
{
    "type":"record",
    "namespace": "org.hamba.avro",
    "name":"X",
    "fields":[{"name":"value", "type": ["null", "int"], "default": {}]
}
```

Note the default value being an empty object instead of `null` data type.

I identified the root cause in how `Field.MarshalJSON` handle fields with default values and prepared a pull request with a fix and updated tests to check this particular use case. I hope it helps.
