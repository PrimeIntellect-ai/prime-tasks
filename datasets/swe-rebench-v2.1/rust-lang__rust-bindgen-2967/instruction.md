`ParseCallbacks::field_visibility` is not called for new type aliases
Given a header file

```c
typedef const char *  VCL_STRING;
```

I would like to create a new alias type:

```rust
let bindings = bindgen::Builder::default()
    .header("src/wrapper.h")
    .parse_callbacks(Box::new(my_callbacks))
    .new_type_alias("VCL_STRING")
    .generate();
```

The above code generates this Rust code:

```rust
pub struct VCL_STRING(pub *const ::std::ffi::c_char);
```

My `my_callbacks` instance implements `field_visibility` callback, but it never gets called for the `VCL_STRING` type - thus I have no way for the field to be created as private or crate-public.
