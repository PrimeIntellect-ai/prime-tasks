Add a way to construct a leaf error without wrapping it in a Result
Right now, sometimes we end up with code like

```rust
Variant.fail::<()>.unwrap_err()
```

This usually occurs when interoperating with systems that already have a `Result`, such as when used in `Result::map_err`.

We could add a new function that just generates the error, not wrapping it.

---

Related but different from the comment in #46:

>  manually construct an error variant with a source error

### Additional contract requirements

- Leaf-error selectors must expose a `build(self) -> Error` method that consumes the selector and returns the concrete error value directly, not a `Result`.
