Self keyword inside macro invocations in trait impl
Issue #73 only revealed part of the problem, and only part of it was fixed.

Since Merge Request #74 `Self` inside macro invocation works when used in the trait declaration, but the issue persists in the trait impl. See this example:

```rust
use async_trait::async_trait;

struct Foo;

#[async_trait]
pub trait Example {
    const ASSOCIATED: &'static str;

    async fn associated(&self) {
        println!("Associated:{}", Self::ASSOCIATED); // <-- This works now
    }

    async fn associated2(&self);
}

#[async_trait]
impl Example for Foo {
    const ASSOCIATED: &'static str = "foo";

    async fn associated2(&self) {
        println!("Associated:{}", Self::ASSOCIATED); // <-- This does not
    }
}
```
Compiler output:
```
   Compiling foo v0.1.0 (/tmp/foo)
error[E0433]: failed to resolve: use of undeclared type or module `AsyncTrait`
  --> src/lib.rs:21:35
   |
21 |         println!("Associated:{}", Self::ASSOCIATED);
   |                                   ^^^^ use of undeclared type or module `AsyncTrait`

error: aborting due to previous error

For more information about this error, try `rustc --explain E0433`.
error: could not compile `foo`.

To learn more, run the command again with --verbose.
```

Tested with 0.1.30.

Workaround from original issue (`let`-binding) also works.
