Could we teach object! to accept trailing commas
Right now,

```rust
object!{
  "foo" => "bar",
}
```

fails because of the trailing comma. It would be nicer to accept them, as in the rest of Rust.
