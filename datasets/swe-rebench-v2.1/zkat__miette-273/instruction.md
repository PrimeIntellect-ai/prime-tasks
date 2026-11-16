`#[source]` does not work on `Box<dyn Error + Send + Sync>`
In order to get miette (with thiserror) to render the full error chain I need to be able to add the `#[source]` macro onto the "source" error.

In my project I'm using a boxed error that also needs to be `Send + Sync` like so:

```rust
#[derive(Diagnostic, Error)]
struct MyError {
  #[error("Any Error")]
  #[diagnostic(transparent)]
  AnyError(#[source] Box<dyn Diagnostic + Send + Sync>)
}
```

However that example fails with the following compilation error:

```
error[E0599]: the method `as_dyn_error` exists for reference `&Box<dyn Diagnostic + Send + Sync>`, but its trait bounds were not satisfied

20  |   pub trait Diagnostic: std::error::Error {
    |   ---------------------------------------
    |   |
    |   doesn't satisfy `dyn Diagnostic + Send + Sync: AsDynError<'_>`
    |   doesn't satisfy `dyn Diagnostic + Send + Sync: Sized`
```

I was able to get around the issue by using an `Arc` instead of a `Box` - but I don't need any `Arc` features so it would be great if it worked with `Box`.
