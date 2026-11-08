Allow raw pointers in extern fn signature
See https://github.com/dtolnay/cxx/issues/122#issuecomment-615372359 for the rationale.

```rust
mod ffi {
    extern "C" {
        type T;
        unsafe fn f(_: *mut T);
    }
    extern "Rust" {
        unsafe fn g(_: *mut T);
    }
}
```

The presence of `*const` or `*mut` in a function argument should enforce that the function is marked unsafe.

### Additional contract requirements

When a function argument has a raw pointer type (`*const T` or `*mut T`) and the
function is not marked `unsafe`, the bridge must be rejected with the diagnostic
message exactly:

    pointer argument requires that the function be marked unsafe

This rule applies to both `*const` and `*mut` pointer arguments.
