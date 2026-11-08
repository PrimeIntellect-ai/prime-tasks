Unable to generate flattened enum
I have tried both tagged or untagged enum in struct, not working.

## Code

Tagged:

```rust
use serde::Serialize;
use ts_rs::TS;

#[derive(Serialize, TS)]
#[ts(export)]
struct Foo {
    #[serde(flatten)]
    baz: Bar,
}

#[derive(Serialize, TS)]
#[serde(tag = "tag")]
#[ts(export)]
enum Bar {
    _Baz { a: i32 },
}
```

Untagged:

```rust
use serde::Serialize;
use ts_rs::TS;

#[derive(Serialize, TS)]
#[ts(export)]
struct Foo {
    #[serde(flatten)]
    baz: Bar,
}

#[derive(Serialize, TS)]
#[serde(untagged)]
#[ts(export)]
enum Bar {
    _Baz,
}
```

## Error

```
---- ts::export_bindings_foo stdout ----
thread 'ts::export_bindings_foo' panicked at 'Bar cannot be flattened', [:REDACTED:]/.cargo/registry/src/github.com-1ecc6299db9ec823/ts-rs-6.1.2/src/lib.rs:243:9
```

## Info
version of `ts-rs`: `6.1.2`
version of `rustc`: `rustc 1.60.0 (7737e0b5c 2022-04-04)`
