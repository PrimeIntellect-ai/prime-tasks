Deriving `EnumTryAs` on an enum with field attributes produces unparsable tokens
Deriving `EnumTryAs` on an enum with field attributes like
```rust
#[derive(EnumTryAs)]
enum Foo {
    Unnamed(#[allow(deprecated)] SomeType),
}
```

fails with the following errors :
```
error: proc-macro derive produced unparsable tokens
 --> strum_tests/tests/enum_try_as.rs:5:10
  |
5 | #[derive(EnumTryAs)]
  |          ^^^^^^^^^
```
```
error: expected type, found `#`
 --> strum_tests/tests/enum_try_as.rs:7:12
  |
7 |     Unamed(#[allow(deprecated)] SomeType),
  |            ^ expected type

```
