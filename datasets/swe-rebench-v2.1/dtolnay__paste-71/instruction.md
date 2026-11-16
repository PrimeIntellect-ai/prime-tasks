"Expected identifier after `:` error" when `::` is used inside attribute
This simple example:

```rust
macro_rules! a { (#[x = $x:ty]) => {}; }
paste::paste!(a!(#[x = foo::Bar]));
```

Fails with the error message:

```
error: expected identifier after `:`
 --> src/lib.rs:3:27
  |
3 | paste::paste!(a!(#[x = foo::Bar]));
  |                           ^^
```

It seems like `paste!` is treating the attribute as a doc attribute even though it isn't.
