Do not require Sync on unused shared reference arguments
```rust
use async_trait::async_trait;

#[async_trait]
trait Generic<T> {
    async fn takes_ref(&self, thing: &T);
}

#[async_trait]
impl<T> Generic<T> for () {
    async fn takes_ref(&self, _: &T) {}
}
```

This currently fails because it expands to something like:

[HIDDEN]

in which the anonymous future type captures a local variable of type `&T`, implying a need for `T: Sync` in order to get a `Send` future.

```console
error: future cannot be sent between threads safely
  --> src/main.rs:10:38
   |
10 |     async fn takes_ref(&self, _: &T) {}
   |                                      ^^ future created by async block is not `Send`
   |
note: captured value is not `Send` because `&` references cannot be sent unless their referent is `Sync`
  --> src/main.rs:10:31
   |
8  | #[async_trait]
   | -------------- in this procedural macro expansion
9  | impl<T> Generic<T> for () {
10 |     async fn takes_ref(&self, _: &T) {}
   |                               ^ has type `&T` which is not `Send`, because `T` is not `Sync`
   = note: required for the cast from `[async block@src/main.rs:10:38: 10:40]` to the object type `dyn Future<Output = ()> + Send`
   = note: this error originates in the attribute macro `async_trait` (in Nightly builds, run with -Z macro-backtrace for more info)
help: consider restricting type parameter `T`
   |
9  | impl<T: std::marker::Sync> Generic<T> for () {
   |       +++++++++++++++++++
```

The following compiles:

```rust
#[async_trait]
impl<T: Sync> Generic<T> for () {
    async fn takes_ref(&self, _: &T) {}
}
```

However that `T: Sync` bound should be unnecessary as long as the `&T` argument is unused within the future.
