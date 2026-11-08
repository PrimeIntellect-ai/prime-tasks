Can not use in literals?
<!--  ❤️  -->


```rust
use paste::paste;
macro_rules! vec_insert {
    ($bit: tt) => {
        paste! {
            fn [<vector_insert_ $bit _bit>](insert_size: usize) {
                let mut [<vec_ $bit>] = Vec::new();
                for _ in 0..insert_size {
                    [<vec_ $bit>].insert(0, [<1_u $bit>]);
                }
            }
        }
    };
}

vec_insert!(32);
```

expected to expand into

```rust
fn vector_insert_32_bit(insert_size: usize) {
    let mut vec_32 = Vec::new();
    for _ in 0..insert_size {
        vec_32.insert(0, 1_u32);
    }
}
```

but it show error:
\`"1_u32"\` is not a valid identifier

Can paste used in literal such as 1_u32?

### Additional contract requirements

- For an invalid paste of `0f`, the diagnostic must be `error: expected identifier, found `0f``.
- For this invalid paste, report the diagnostic at the outer `paste!` invocation and include the note `= note: this error originates in the macro `paste` (in Nightly builds, run with -Z macro-backtrace for more info)`.
