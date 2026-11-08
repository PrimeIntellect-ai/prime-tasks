Failed to resolve `self` in path
Macro doesn't handle when `self` is used as path.
```rust
use async_trait::async_trait; // 0.1.48

fn bar() {}

#[async_trait]
trait Foo {
    async fn bar(&self) {
        self::bar()
    }
}
```
```rust
error[E0433]: failed to resolve: use of undeclared crate or module `__self`
 --> src/lib.rs:8:9
  |
8 |         self::bar()
  |         ^^^^ use of undeclared crate or module `__self`
```
[Playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=9567f3a7c893e1eb8da5256043246c9b)
