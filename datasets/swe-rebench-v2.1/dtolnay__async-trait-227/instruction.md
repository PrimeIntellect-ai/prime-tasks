Attributes on impl parameters are not forwarded to body
Heya, I was implementing a trait function with `#[cfg(..)]` in its parameters, and encountered the following error:

```rust
// within trait impl
async fn cfg_param(
    &self,
    #[cfg(not(feature = "something"))] param: u8,
    #[cfg(feature = "something")] _unused: u8,
    //                            ^^^^^^^
    // cannot find value `_unused` in this scope
) -> u8 {
    #[cfg(not(feature = "something"))]
    { param }
    #[cfg(feature = "something")]
    { 1 }
}
```

The expanded code body shows:

```rust
let __self = self;
let param = param;
let _unused = _unused;
let __ret: u8 = { #[cfg(not(feature = "something"))] { param } };
#[allow(unreachable_code)] __ret
```

Since `_unused` is not present in the function signature, the expanded code should likely just omit it.

#227 forwards the attributes, such that the expanded code returns:

```rust
let __self = self;
[HIDDEN]
let __ret: u8 = { #[cfg(not(feature = "something"))] { param } };
#[allow(unreachable_code)] __ret
```

The `_unused` statement isn't present since it's been removed by the expansion.
