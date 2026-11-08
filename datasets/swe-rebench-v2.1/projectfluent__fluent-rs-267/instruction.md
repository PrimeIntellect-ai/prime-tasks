[DX Enhancement] Make fluent_args works with trailing comma
Currently, this code won't compile:
```rust
fluent_args! {
  "name" => "World",
}
```
Because fluent_args! doesn't handle trailing commas. The fix would be trivial, so I could do a PR if this is appreciated.
