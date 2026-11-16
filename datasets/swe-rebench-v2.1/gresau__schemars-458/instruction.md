type annotations needed cannot infer type
## version

schemars = "1.0.3"


## reproduce

```rs
use {schemars::JsonSchema, serde::Deserialize, std::path::PathBuf};

#[derive(Debug, Deserialize, JsonSchema)]
pub enum Version {
    V1(),
}
```

## error

```
error[E0282]: type annotations needed
 --> path/to/config.rs:3:30
  |
3 | #[derive(Debug, Deserialize, JsonSchema)]
  |                              ^^^^^^^^^^ cannot infer type
  |
  = note: this error originates in the derive macro `JsonSchema` (in Nightly builds, run with -Z macro-backtrace for more info)


```

### Additional contract requirements

- When generating a schema for an empty tuple variant, its array schema must be `{ "type": "array", "maxItems": 0 }`, with no `prefixItems` or `minItems`.
