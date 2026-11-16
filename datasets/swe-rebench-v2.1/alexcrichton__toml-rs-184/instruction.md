Serializing Nested Array of Tables incorrectly
The TOML table equivalent to the following JSON:

```json
{"table": [
  {"inner": [ {} ] }
]}
```

should serialize into

```toml
[[table]]
  [[table.inner]]
```

Instead, it serializes into:
```toml
[[table.inner]]
```

which is equivalent to `{'table': {'inner': [{}]}}`.

Found with https://github.com/rust-fuzz/targets/pull/72.
