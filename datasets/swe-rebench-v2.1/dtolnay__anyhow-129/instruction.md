Consider allowing 1-argument `ensure!`
The `ensure!` macro currently takes a condition argument (bool) followed by format arguments for the error message.
https://docs.rs/anyhow/1.0.34/anyhow/macro.ensure.html

```rust
    ($cond:expr, $fmt:expr, $($arg:tt)*) => { ... };
```

It would be reasonable to also support 1-argument `ensure!` with only the condition argument.

```rust
ensure!(depth <= MAX_DEPTH);
```

If the condition is false, the resulting error would be produced from the `stringify` of the condition expression. This would match the API of the standard library's `assert!` macro. https://doc.rust-lang.org/std/macro.assert.html
