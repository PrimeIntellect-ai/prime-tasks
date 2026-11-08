Allow wildcard argument names in extern function signature
Currently we reject this for no particular reason. Seems like an oversight.

```rust
#[cxx::bridge]
mod ffi {
    extern "C" {
        fn repro(_: &str);
    }
}
```

```console
error[cxxbridge]: unsupported signature

    ┌── src/main.rs:4:18 ───
    │
  4 │         fn repro(_: &str);  // but `s: &str` works
    │                  ^^^^^^^ unsupported signature
```
