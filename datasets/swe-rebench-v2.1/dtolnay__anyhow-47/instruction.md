Usage of `bail!(error)` loses the context of `error`
I was in a situation recently where I was doing:

```rust
match some_result {
    Ok(()) => {}
    Err(e) => {
        if !err_is_ok(e) {
            bail!(e);
        }
    }
}
```

in this case `e` was actually of type `anyhow::Error` so a `return Err(e)` would have worked just fine, but I was surprised when this `bail!()` lost the context of the error of `e`, presumably because it called `.to_string()` on the result and lost all the context information.

### Additional contract requirements

- `bail!(e)` where `e` is an `anyhow::Error` must preserve the context of `e`; the
  error returned from the enclosing function must retain `e`'s original source
  chain (i.e. `Error::source` on the returned error exposes the same underlying
  error that `e` exposed), rather than stringifying `e` and discarding its context.
