Inline trait bounds from error types should not be included in struct names
[@mikeando points out](https://github.com/shepmaster/snafu/pull/54#issuecomment-486034916) that we don't preserve user-provided trait bounds when they are provided inline:

```rust
#[derive(Debug, Snafu)]
enum InlineBoundsError<T: Display> {
    #[snafu(display("Boom: {}", value))]
    Boom { value: T },
}
```

Mirror issue of #53

### Additional contract requirements

- The `Snafu` derive must support error types whose generic parameters carry trait bounds, whether the bounds are written inline (`Error<T: Display>`) or in a `where` clause (`Error<T> where T: Display`), and tuple-struct wrappers over such error types (`ApiError<T: Debug + Display>(Error<T>)`).
- A `Boom { value }` variant annotated with `#[snafu(display("Boom: {}", value))]` must display as `Boom: <value>`.
- A tuple-struct wrapper deriving `Snafu` must forward `Display` to its inner error and implement `std::error::Error`, so displaying the wrapper yields the inner error's display text.
