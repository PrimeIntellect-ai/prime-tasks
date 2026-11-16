Multiple FFI blocks referencing types from one another
I have two files requiring FFI, `json.rs` and `basevalue.rs`. I'd like to keep the FFI blocks local to those files, instead of having a central `ffi.rs`, but right now this is not possible.

My FFI block in `basevalue.rs`.
```rust
#[cxx::bridge(namespace = base)]
pub mod ffi {
    extern "C" {
        include!("base/values_rust.h");
        type RawOptionalBaseValue;
        fn RustOptionalBaseValueSetString(v: &mut RawOptionalBaseValue, value: &str);
        fn RustOptionalBaseValueSetBool(v: &mut RawOptionalBaseValue, val: bool);
        // etc.
    }
}
```

My FFI block in `json.rs`:
```rust
#[cxx::bridge(namespace = base)]
pub mod ffi {
    extern "Rust" {
        pub fn decode_json(
            bv: UniquePtr<RawOptionalBaseValue>,
            json: &str
        ) -> bool;
    }
}
```

Note that the `json.rs` block references a type from the `basevalue.rs` block.

This gives
```
error[cxxbridge]: unsupported type
```

which is unsurprising, and I imagine is really hard to solve.

(The exact code above is significantly simplified so obviously don't try to build it; if this issue isn't as "known" as I expect, let me know and I'll make a minimal test case).

### Additional contract requirements

- A type alias in an `extern "Rust"` block, such as `type Alias = crate::Type;`, must be rejected with the exact diagnostic message `type alias in extern "Rust" block is not supported`.
- If an `extern "C"` type alias names a different C++ type identity than its aliased Rust type, compilation must emit the exact diagnostic line `expected a tuple with 15 elements, found one with 17 elements`.
- For an `extern "Rust"` alias declaration `type Alias = crate::Type;`, the diagnostic must underline the entire declaration, from `type` through the terminating `;`.
- For `type ByteRange = crate::here::StringPiece;` in namespace `folly`, the `E0271` diagnostic must underline the entire declaration and identify `<here::StringPiece as cxx::extern_type::ExternType>::Id` as mismatching `(cxx::f, cxx::o, cxx::l, cxx::l, cxx::y, (), cxx::B, cxx::y, cxx::t, cxx::e, cxx::R, cxx::a, cxx::n, cxx::g, cxx::e)`. Its notes must give expected tuple `(cxx::f, cxx::o, cxx::l, cxx::l, cxx::y, (), cxx::B, cxx::y, cxx::t, cxx::e, cxx::R, cxx::a, cxx::n, cxx::g, cxx::e)` and found tuple `(cxx::f, cxx::o, cxx::l, cxx::l, cxx::y, (), cxx::S, cxx::t, cxx::r, cxx::i, cxx::n, cxx::g, cxx::P, cxx::i, cxx::e, cxx::c, cxx::e)`.
