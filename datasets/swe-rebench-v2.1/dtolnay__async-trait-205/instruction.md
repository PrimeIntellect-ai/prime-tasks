Use parentheses to disambiguate impl Trait
```rust
use async_trait::async_trait;

#[async_trait]
pub trait Trait {
    async fn f(arg: &impl Trait);
}
```

currently fails with:

```console
error: ambiguous `+` in a type
 --> src/main.rs:5:22
  |
5 |     async fn f(arg: &impl Trait);
  |                      ^^^^^^^^^^ help: use parentheses to disambiguate: `(impl 'async_trait + Trait)`
```
