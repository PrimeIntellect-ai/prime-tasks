Keep ordering of deserialized maps
Serde's yaml deserialization supports maintaining the order of map types (at least in yaml/json, haven't looked at other formats) [HIDDEN]. Quickly perusing through `config-rs`, it looks like the `table` value uses `HashMap` and so will always lose the ordering of a map.

[HIDDEN] but since that type is exposed to the API, it could be considered a breaking change. Would the project be receptive to such a change?

### Additional contract requirements

- Export a public type alias `Map<K, V>` from the crate root (`config::Map`). When the `preserve_order` feature is disabled it must resolve to `std::collections::HashMap<K, V>`; when enabled it must resolve to an order-preserving map type.
- Add a cargo feature named `preserve_order`. When enabled, maps produced by deserializing configuration (for example through `Config::get`) preserve the insertion order of the source data.
- `AsyncSource::collect` must return `Result<Map<String, Value>, ConfigError>`.
