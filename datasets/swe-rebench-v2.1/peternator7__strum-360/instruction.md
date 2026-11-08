strum-macros 0.26.3 breaks `no_std` build
With 0.26.3, the emitted code when using `derive(strum::Display)` uses `format!` unconditionally. This requires the surrounding code to `use format::alloc;`, which seems like an unfortunate breaking change to me.

Example `main.rs`:

```rust
#![no_std]

#[derive(strum::Display)]
enum Foo {
    Bar
}

fn main() {
}
```

Sample `Cargo.toml`:

```toml
[package]
name = "strumtest"
version = "0.1.0"
edition = "2021"

[dependencies]
strum = { version = "0.26.2", features = ["derive"] }
strum_macros = { version = "0.26.3" }
```

If you downgrade to `=0.26.2` the build works, otherwise it aborts with:

```
error: cannot find macro `format` in this scope
 --> src/main.rs:3:10
  |
3 | #[derive(strum::Display)]
  |          ^^^^^^^^^^^^^^
  |
  = note: this error originates in the derive macro `strum::Display` (in Nightly builds, run with -Z macro-backtrace for more info)

error: could not compile `strumtest` (bin "strumtest") due to 1 previous error
```

I think it's okay to require the surrounding `no_std` code to `use alloc::format;` when using `strum`, but it would be great if this requirement could come with a new major version (0.27) instead.
