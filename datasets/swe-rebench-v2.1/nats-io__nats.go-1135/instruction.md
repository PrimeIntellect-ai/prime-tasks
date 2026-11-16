Add error value for when a KV key already exists

### Additional contract requirements

- When `KeyValue.Create` is called for an existing key, it must return `ErrKeyExists`.
