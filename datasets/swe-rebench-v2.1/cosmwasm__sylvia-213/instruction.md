Methods in multitest proxy are generated using interfaces module as Ident instead of Path
# Current behavior

If we specify module in which interface is defined as `Path` `sylvia` will treat it as `Ident`.

```rust
#[contract]
#[messages(crate::interface as Interface)]
impl Interface for Contract {
...
}
```

will generate f.e.

```rust
let msg = crate::ExecMsg::new(...);
```

# Expected behavior

`Sylvia` should use full path.

```rust
let msg = crate::interface::ExecMsg::new(...);
```
