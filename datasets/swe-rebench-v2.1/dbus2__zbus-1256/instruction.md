`DeserializeDict` fails if struct field is named 'key'
The following fails

```Rust
#[derive(DeserializeDict, Type)]
#[zvariant(signature = "a{sv}")]
pub struct OwnedProperties {
    key: String,
    val: OwnedValue,
}
```

like so:
```Term
error[E0308]: mismatched types
 --> src/main.rs:7:10
  |
7 | #[derive(DeserializeDict, Type)]
  |          ^^^^^^^^^^^^^^^
  |          |
  |          expected `&str`, found `Option<_>`
  |          expected due to the type of this binding
  |
  = note: expected reference `&str`
                  found enum `std::option::Option<_>`
  = note: this error originates in the derive macro `DeserializeDict` (in Nightly builds, run with -Z macro-backtrace for more info)
help: consider using `Option::expect` to unwrap the `std::option::Option<_>` value, panicking if the value is an `Option::None`
  |
7 | #[derive(DeserializeDict.expect("REASON"), Type)]
  |
```

Problem goes away as soon as the field 'key' is renamed to something else.
