Support builtin derive attributes helper attributes
The `Default` derive now has a helper attribute defined called `default`. We don't support those yet.
See https://doc.rust-lang.org/src/core/default.rs.html#182
```rs
#[rustc_builtin_macro(Default, attributes(default))]
#[stable(feature = "builtin_macro_prelude", since = "1.38.0")]
#[allow_internal_unstable(core_intrinsics)]
pub macro Default($item:item) {
    /* compiler built-in */
}
```
we need to parse the `#[rustc_builtin_macro(Default, attributes(default))]` line
