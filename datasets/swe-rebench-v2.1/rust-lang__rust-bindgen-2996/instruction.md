Handle the new `clippy::manual_c_str_literals` lint
Clippy 1.83 introduced [manual_c_str_literals](https://rust-lang.github.io/rust-clippy/master/index.html#/manual_c_str_literals) on this type of generated code:

```rust
#[allow(unsafe_code)]
pub const VSL_CLASS: &::std::ffi::CStr =
    unsafe { ::std::ffi::CStr::from_bytes_with_nul_unchecked(b"Log\0") };
```

```
warning: calling `CStr::new` with a byte string literal
   --> .../out/bindings.rs:708:14
    |
708 |     unsafe { ::std::ffi::CStr::from_bytes_with_nul_unchecked(b"Log\0") };
    |              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ help: use a `c""` literal: `c"Log"`
    |
    = help: for further information visit https://rust-lang.github.io/rust-clippy/master/index.html#manual_c_str_literals
    = note: `#[warn(clippy::manual_c_str_literals)]` on by default
```

## Possible solutions
* introduce a new `generate_cstr_literal(bool)` flag
* change `generate_cstr(bool)` to take an enum instead, e.g. `Off, CStrObjects, CStrLiterals`
* add `#[allow(clippy::manual_c_str_literals)]` to each instance of calling `from_bytes_with_nul_unchecked`

### Additional contract requirements

- With `--generate-cstr` and Rust target 1.77, generate these declarations for the corresponding constants:

```rust
pub const MY_STRING_UTF8: &::std::ffi::CStr = c"Hello, world!";
pub const MY_STRING_INTERIOR_NULL: &::std::ffi::CStr = c"Hello,";
pub const MY_STRING_NON_UTF8: &::std::ffi::CStr = c"ABCDE\xFF";
```
