Support opaque Rust types in a rust::Slice
Currently only primitives and shared types are supported in a slice in the FFI.

The following is currently rejected, but it should be possible to support:

```rust
#[cxx::bridge]
mod ffi {
    extern "Rust" {
        type MyType;
    }

    unsafe extern "C++" {
        fn f(slice: &[MyType]);
    }
}
```

The slice iterators and indexing operations will need to [HIDDEN]

### Additional contract requirements

- Iteration and indexing over slices of opaque Rust types must access the correct elements.
