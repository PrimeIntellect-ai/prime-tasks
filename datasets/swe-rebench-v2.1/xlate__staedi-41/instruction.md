Allow SchemaFactory property for context of relative schemaLocation URLs
Add property to allow resolution of relative `schemaLocation` URLs given in schema `include` elements.

`SchemaFactory.SCHEMA_LOCATION_URL_CONTEXT`

### Additional contract requirements

- `SchemaFactory.isPropertySupported(SchemaFactory.SCHEMA_LOCATION_URL_CONTEXT)` returns `true`.
- The value of `SCHEMA_LOCATION_URL_CONTEXT` is a base URL. It may be given either as a `java.net.URL` object or as a string holding an absolute URL.
- When the property is set, a relative `schemaLocation` in an `include` element of a schema read by the factory is resolved against that base URL, and the included schema's types are loaded into the schema.
