compilation failure when mixing `default` with `NonZeroU8`
A schema like this...

```json
    {
      "type": "object",
      "properties": {
        "x": {
          "type": "integer",
          "format": "uint8",
          "minimum": 1,
          "default": 1
        }
      }
    }
```

... turns into code like this...

```rust
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct X {
    #[serde(default = "defaults::default_u64::<std::num::NonZeroU8, 1>")]
    pub x: std::num::NonZeroU8,
}
impl From<&X> for X {
    fn from(value: &X) -> Self {
        value.clone()
    }
}
pub mod defaults {
    pub(super) fn default_u64<T, const V: u64>() -> T
    where
        T: std::convert::TryFrom<u64>,
        <T as std::convert::TryFrom<u64>>::Error: std::fmt::Debug,
    {
        T::try_from(V).unwrap()
    }
}
```

Which is as-intended: `defaults::default_u64` is intended to produce the default value that we want.

However!
```
error[E0277]: the trait bound `NonZeroU8: From<u64>` is not satisfied
```

The `NonZero*` types implement `TryFrom` for their corresponding primitive type, but not other primitive types. This appears to be a point of principle: https://github.com/rust-lang/rust/pull/72712#issuecomment-635679120

So: cute as this would be, we need a different approach. Some options:

1. Use some new trait that takes the place of `TryFrom` but has more implementations. This might be kind of annoying because we'd probably dump all this code into the `mod defaults` by default (no pun intended).
1. We could generate `default_non_zero_u64`... it would only create a little bit of annoying code to determine which one to use.
1. We could generate a function for each default. This would be fine, but it's been nice to share the integer implementations
1.  Parameterize `default_u64` with two types (rather than one) i.e. the output type and an "intermediate type": `defaults::default_u64::<NonZeroU8, u8>`

### Additional contract requirements

For a schema field represented as `NonZeroU8` with a valid integer default, the generated Rust must compile and use that schema default when Serde deserializes an object in which the field is missing.
