Allow specifying attributes in `impl` mode
I'm considering `cfg`-gating the use of `bitflags!` in my libraries, and to that end it would be nice if it was possible to apply attributes to the generated `impl`s as well.

The naive solution would be:
```rust
pub struct Flags(u8);

#[cfg(feature = "bitflags")]
bitflags! {
    impl Flags: u8 {
        // ...
    }
}
```

However, that works poorly with the `doc_cfg` (and `doc_auto_cfg`) feature, as the attribute is only applied to the macro, and isn't passed down to each output item.

Instead, I would like to be able to do the following:
```rust
#![feature(doc_cfg)]

pub struct Flags(u8);

#[cfg(feature = "bitflags")]
bitflags! {
    #[doc(cfg(feature = "bitflags"))]
    impl Flags: u8 {
        // ...
    }
}
```
