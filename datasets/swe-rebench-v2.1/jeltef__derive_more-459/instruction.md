Optional source for Error
I’d like to be able to use `derive_more` with optional sources, like:

```rs
#[derive(derive_more::Error, derive_more::Display, Debug)]
#[display("it’s an error")]
struct MyErr {
    source: Option<Box<dyn std::error::Error + Send + Sync + 'static>>,
}
```

Notably, this does work with `thiserror`.

At the moment this gives:

```
error[E0599]: the method `as_dyn_error` exists for enum `Option<Box<dyn Error + Send + Sync>>`, but its trait bounds were not satisfied
    |
187 | #[derive(derive_more::Error, derive_more::Display, Debug)]
    |          ^^^^^^^^^^^^^^^^^^
    |
571 | pub enum Option<T> {
    | ------------------ doesn't satisfy `_: AsDynError<'_>` or `_: Error`
    |
    = note: the following trait bounds were not satisfied:
            `std::option::Option<std::boxed::Box<dyn derive_more::Error + std::marker::Send + std::marker::Sync>>: derive_more::Error`
            which is required by `std::option::Option<std::boxed::Box<dyn derive_more::Error + std::marker::Send + std::marker::Sync>>: derive_more::__private::AsDynError<'_>`
note: the method `as_dyn_error` exists on the type `std::boxed::Box<(dyn derive_more::Error + std::marker::Send + std::marker::Sync + 'static)>`
    |
9   |     fn as_dyn_error(&self) -> &(dyn Error + 'a);
    |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    = note: this error originates in the derive macro `derive_more::Error` (in Nightly builds, run with -Z macro-backtrace for more info)
```

### Additional contract requirements

An optional source field that holds no value (`None`) must report no source.
