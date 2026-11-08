Missing table config throws non user friendly error
When building metadata for entity with missing table configuration, currently misleading error saying "TypeError: Cannot read property 'partitionKey' of undefined", this should be "Missing required table config" or something

### Additional contract requirements

- Add a public error class `MissingRequiredTableConfig` exported from `@typedorm/common` that extends `Error`.
- The error's `name` is `"MissingRequiredTableConfig"`.
- The error's `message` is descriptive and indicates that the entity must have either a connection-level table or an entity-level table defined.
