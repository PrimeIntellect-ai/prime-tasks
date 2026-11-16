array types in `Query` don't emit items
If a struct like
```rust
#[derive(Deserialize, Apiv2Schema)]
    struct BadgeParams {
        list: Vec<String>,
    }
```

The parameters that are emitted are:
```rust
"parameters": [
          {
            "in": "query",
            "name": "list",
            "required": true,
            "type": "array"
          },
        ],
```

it is missing a
```rust
"items": { "type": "string" }
```

I believe that there needs to be a mapping from `Option<DefaultSchemaRaw>` to `Option<Items>` under `DefaultOperationRaw::parameters`:
https://github.com/wafflespeanut/paperclip/blob/bdf51fe24bf3e24c0438e1909209d13ea5c74876/core/src/v2/actix.rs#L316-L325

I'll try to make the change but I feel like I'm stabbing in the dark a bit at whether this is what needs to be done.
