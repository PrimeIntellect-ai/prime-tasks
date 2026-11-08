`Option` no longer has a default of null as of v0.8.18
In schemars v0.8.17, an `Option` with a default of `None` results in `"default": null`.

```rust
use schemars::{schema_for, JsonSchema};

#[derive(JsonSchema, Default)]
#[schemars(default = "Self::default")]
pub struct MyStruct {
    pub my_int: Option<i32>,
}

fn main() {
    let schema = schema_for!(MyStruct);
    println!("{}", serde_json::to_string_pretty(&schema).unwrap());
}
```

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "MyStruct",
  "type": "object",
  "properties": {
    "my_int": {
      "default": null,
      "type": [
        "integer",
        "null"
      ],
      "format": "int32"
    }
  }
}
```

In schemars v0.8.18 (and the latest v0.8.20), the same `Option` has no default.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "MyStruct",
  "type": "object",
  "properties": {
    "my_int": {
      "type": [
        "integer",
        "null"
      ],
      "format": "int32"
    }
  }
}
```

I'm not sure if this was an intentional change, but it seems to me like having `"default": null` would be more expected, especially given that the example used the `#[schemars(default = "Self::default")]` attribute.
