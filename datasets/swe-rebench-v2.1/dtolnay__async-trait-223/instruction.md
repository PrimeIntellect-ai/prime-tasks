Defaulted method with `self: Arc<Self>` doesn't work
`Arc` generates a `where Self: Send` bound, but for `Arc` it is not enough - it requires also `T: Sync` to be `Send`.  This make the following code failing to compile:
```rust
#[async_trait]
trait Trait {
    async fn foo(self: Arc<Self>) {}
}
```
https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=add1c3d15459405538a453e3c9a504a6
```
error: future cannot be sent between threads safely
 --> src/lib.rs:7:35
  |
7 |     async fn foo(self: Arc<Self>) {}
  |                                   ^^ future created by async block is not `Send`
  |
note: captured value is not `Send`
 --> src/lib.rs:7:18
  |
7 |     async fn foo(self: Arc<Self>) {}
  |                  ^^^^ has type `Arc<Self>` which is not `Send`
  = note: required for the cast to the object type `dyn Future<Output = ()> + Send`
```
[Adding `Sync` as a supertrait works](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=0c2bccdc20c8df461d014bd9a25b131e), but ideally the macro should also add a `Self: Sync` bound (even though I don't know how it can identify `Arc` being used), or at least document that.

### Additional contract requirements

- A defaulted async trait method with receiver `self: Arc<Self>` must produce a `Send` future when the implementing type is `Send + Sync`; documenting this limitation is not sufficient.
