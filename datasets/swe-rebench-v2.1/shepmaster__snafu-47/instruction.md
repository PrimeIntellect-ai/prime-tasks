Add the ability to make an opaque error type
Having a public enum for an error type means that the enum *variants* are also public and a part of the API. This isn't always desired.

We could add a way to delegate the important traits while hiding details:

```rust
#[derive(SnafuOpaque)]
// or `Snafu` + `#[snafu(opaque)]`?
// or just know that it's a tuple struct with one member?
struct Error(InternalError)

impl Error {
    // Deliberately chosen methods here
    fn is_caused_by_network(&self) -> bool { /* ... */ }
}

#[derive(Snafu)]
enum InternalError {
    Alpha,
    Beta,
}
```

### Additional contract requirements

An opaque error type is created by deriving `Snafu` for a tuple struct with exactly one field. The resulting type wraps that field's type and implements `std::error::Error`, `std::fmt::Display` (delegating to the wrapped error), and `From<Inner>`, where `Inner` is the wrapped type.

Deriving `Snafu` for any other shape is rejected with a diagnostic:
- for a union, the diagnostic contains ``Can only derive `Snafu` for an enum or a newtype``;
- for a unit struct or a struct with named fields, the diagnostic contains `tuple structs`;
- for a tuple struct with any number of fields other than one, the diagnostic contains `exactly one field`.
