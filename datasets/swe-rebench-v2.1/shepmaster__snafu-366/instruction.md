Breaking changing 0.7.2
I had an error roughly defined as such:

```
#[derive(Debug, Snafu)]
enum Error {
    Variant1 {
        #[snafu(source(from(String, Into::into)))]
        source: Box<dyn std::error::Error + Send + Sync>,
    },

    // ...
}

fn return_error() -> Result<(), String> {
    Err("nope!".to_string())
}

return_error().context(Variant1Snafu)?;
```

In 0.7.1 this was acceptable. In 0.7.2, it is now saying that `String` does not implement `std::error::Error` which is a requirement for `AsErrorSource`. [HIDDEN]

### Additional contract requirements

- For a struct or enum variant with a source field annotated `#[snafu(source(from(T, expr)))]`, its generated selector must accept a source value of type `T` through both `Result::context` and `IntoError::into_error`. The resulting error's source field must contain the value produced by `expr`.
