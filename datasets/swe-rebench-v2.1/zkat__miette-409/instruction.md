Implement `WrapError` for `Option`
`anyhow` [implements it's `Context` trait on options](https://docs.rs/anyhow/latest/anyhow/trait.Context.html#impl-Context%3CT,+Infallible%3E-for-Option%3CT%3E). This helps avoid some boilerplate:

```rust
use anyhow::Context;

let map = HashMap::from([("a", 1), ("b", 2), ("c", 3)]);
let _ = map.get("d").with_context(|| format!("Key 'd' was missing from map: {map:?}"))?;
```

Currently the best way to do this with `miette` is by using a `let else` then `bail!`:

```rust
use miette::bail;

let map = HashMap::from([("a", 1), ("b", 2), ("c", 3)]);
let Some(_) = map.get("d") else {
    bail!("Key 'd' was missing from map: {map:?}"));
};
```

I'm willing to implement this if desired

### Additional contract requirements

- `Option<T>` values support the same `context` and `with_context` methods that `Result` values already get from the `WrapErr` trait, so an absent value can be turned into a miette error without a manual `let else`/`bail!`.
- For `Some(value)`, the call returns `Ok(value)`.
- For `None`, the call returns an error whose displayed message is exactly the supplied context.
- The closure given to `with_context` is only called when the value is `None`.
