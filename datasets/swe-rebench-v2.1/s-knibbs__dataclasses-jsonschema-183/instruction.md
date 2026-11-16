Schema for tuple types incompatible with OpenAPI Spec 3.0
The following schema is valid for jsonschema but not for openapi 3.0:

```json
{
  "type": "array",
  "minItems": 2,
  "maxItems": 2,
  "items": [{"type": "number"}, {"type": "number"}]
}
```

For the above case, since both tuple items have the same type, we can replace the above with this:

```json
{
  "type": "array",
  "minItems": 2,
  "maxItems": 2,
  "items": {"type": "number"}
}
```
