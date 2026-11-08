Add `#[strum(transparent)]` argument
This crate is amazing for tackling a lot of boilerplate code and also ensuring variant name changes propagate to the trait implementations. I use `AsRefStr` and `EnumString` quite a lot.

However, a lot of times I've found myself in the situation of having something like this:
```rust
enum MyEnum {
    A,
    B,
    C,
    Other(String)
}
```

Afaik there's no way of propagating the `AsRef<str>` or `FromStr` implementations to the underlying `String`. What do you think about implementing a `transparent` argument to the attribute, similar to `#[serde(transparent)]` - only for one field provided in an unnamed/named fashion.

So then we could do:
```rust
#[derive(AsRefStr, EnumStr)]
enum MyEnum {
    A,
    B,
    C,
    #[strum(transparent)]
    Other(String)
}
```

I could try and pick this up if you like the idea. I think it would be handy for a lot of people.

### Additional contract requirements

- The `#[strum(transparent)]` attribute is accepted on an enum variant that has exactly one field, whether that field is unnamed (a tuple field) or named.
- For a variant marked `#[strum(transparent)]`, the `AsRefStr` derive's `as_ref(&self) -> &str` returns the value produced by the inner field's `AsRef<str>` implementation.
- For a variant marked `#[strum(transparent)]`, the `AsStaticStr` derive's `AsStaticRef::as_static(&self) -> &'static str` returns the inner field's static string.
- For a variant marked `#[strum(transparent)]`, the `IntoStaticStr` derive's `<&'static str>::from(&Enum)` conversion returns the inner field's static string.
- For a variant marked `#[strum(transparent)]`, the `Display` derive's `fmt` writes the inner field's `Display` output.
- The `transparent` attribute does not change the `EnumString`/`FromStr` behaviour of the enum.
