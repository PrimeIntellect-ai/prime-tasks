Cannot use `#[doc(alias)]`
The following code:
```rs
bitflags::bitflags! {
  #[doc(alias = "SYMBOLIC_LINK_FLAGS")]
  pub struct SymbolicLinkFlags:u32 {
    #[doc(alias = "SYMBOLIC_LINK_FLAG_DIRECTORY")]
    const DIRECTORY = 0x1;
    #[doc(alias = "SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE")]
    const ALLOW_UNPRIVILEGED_CREATE = 0x2;
  }
}
```
Produces the error:
```
error: `#[doc(alias = "...")]` isn't allowed on expression
  --> src\fs.rs:67:15
   |
67 |         #[doc(alias = "SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE")]
   |               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

### Additional contract requirements

The supplied aliases must remain attached to their corresponding generated bitflags type and flag in generated documentation, where rustdoc search can find them.
