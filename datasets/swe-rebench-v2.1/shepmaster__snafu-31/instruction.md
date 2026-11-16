Allow visibility to be applied to context selectors
My opinion is that error types should be plentiful — each module should have one (or more!) error types. Each error type is only ever constructed by that module (and maybe child modules). Each error type is very tailored to its domain and there are less cases of "but these 31 error variants don't *actually* occur here". This fits really well with SNAFU's default of making context selectors private by default.

However, the concept of a unified error type is present in the Rust ecosystem, and I have found myself wanting to create a child's error for purposes of testing. This would be best served via marking the context selectors with `pub(crate)`. Once we open that can of worms, we can probably allow *any* visibility modifier.

How should we allow users to specify this? My first thoughts are something like this:

```rust
#[derive(Snafu)]
#[snafu::visibility(pub(crate)] // sets the default visibility (uses private if not present)
enum Error {
    Alpha,
    #[snafu::visibility(pub)] // sets the specific visibility (uses the default if not present)
    Beta,
}
```

### Additional contract requirements

- The visibility is specified with an attribute named `snafu_visibility`, written as `#[snafu_visibility = "X"]` where `X` is a Rust visibility modifier such as `pub`, `pub(crate)`, or `pub(in some::path)`. The bare form `#[snafu_visibility]` sets the visibility back to private.
- Applied to the error enum, `snafu_visibility` sets the default visibility for that enum's context selectors; applied to an individual variant, it overrides the default for that variant's context selector. When no `snafu_visibility` is present, context selectors are private.
- A context selector for a variant named `Variant` is a value named `Variant` that exposes an inherent method `fail<T>(self) -> Result<T, Error>` returning the corresponding error variant.
