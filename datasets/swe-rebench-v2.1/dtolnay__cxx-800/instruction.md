Regression in 1.0.40 handling of extern C++ return reference types
With 1.0.40, this code:

```rust
    unsafe extern "C++" {
        include!("rpmostree-clientlib.h");
        fn client_require_root() -> Result<()>;
        type ClientConnection;
        fn new_client_connection() -> Result<UniquePtr<ClientConnection>>;
        fn get_connection<'a>(self: Pin<&'a mut ClientConnection>) -> Pin<&'a mut GDBusConnection>;
        fn transaction_connect_progress_sync(&self, address: &str) -> Result<()>;
    }
```

no longer compiles:

```
error[E0308]: mismatched types
   --> rust/src/lib.rs:26:1
    |
26  | #[cxx::bridge(namespace = "rpmostreecxx")]
    | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ expected struct `Pin`, found `&mut _`
...
381 |         fn get_connection<'a>(self: Pin<&'a mut ClientConnection>) -> Pin<&'a mut GDBusConnection>;
    |                                                                       ---------------------------- expected `Pin<&'a mut cxxrsutil::FFIGDBusConnection>` because of return type
    |
    = note:         expected struct `Pin<&'a mut cxxrsutil::FFIGDBusConnection>`
            found mutable reference `&mut _`
    = note: this error originates in an attribute macro (in Nightly builds, run with -Z macro-backtrace for more info)

error: aborting due to previous error

```

(Associated C++ code is here: https://github.com/coreos/rpm-ostree/blob/bef1fc792655e6a22cc8676949a6a5792686ee2b/src/app/rpmostree-clientlib.h#L37-L56)

It's not clear from the error message what exactly is wrong. It said it found a `&mut _` but the underlined type matches exactly the expected type (`GDBusConnection` is the same type as `cxxrsutil::FFIGDBusConnection`).
