Cargo scripts try to build a nearby `src/lib.rs` if present
### Problem

If I place a script in the same directory as a crate, it uses crate's source files, but does not use crate's dependencies, causing unexpected compilation errors.


### Steps

`./Cargo.toml`:

```toml
[package]
name = "mainpackage"
version = "0.1.0"
edition = "2021"

[dependencies]
hex = "0.4.3"
```

`./src/lib.rs`:

```rust
use hex;
```

`./script.rs`:

```rust
#!/usr/bin/env cargo +nightly -Zscript

//! ```cargo
//! [package]
//! edition = "2021"
//! ```

fn main() {
}
```

----

Running `./script.rs` causes:

```text
warning: `package.edition` is unspecified, defaulting to `2021`
   Compiling script v0.0.0 (…/mainpackage)
error[E0432]: unresolved import `hex`
 --> src/lib.rs:1:5
  |
1 | use hex;
  |     ^^^ no external crate `hex`

```


This looks broken, because `src/lib.rs` is compiled with scripts dependencies, not its usual crate dependencies.


### Possible Solution(s)


I would expect `Cargo.toml` and `src/` to be completely ignored by the scripts. Or if they're not ignored, to be compiled correctly as a library and included as an external crate in the script (like `tests/` or `main.rs` get). But compiling the crate, but with a wrong `Cargo.toml` context seems like the worst of both.


### Notes

BTW, "warning: `package.edition` is unspecified, defaulting to `2021`" is printed, even though I've tried to specify it in all places.


### Version

```text
cargo 1.82.0-nightly (8f40fc59f 2024-08-21)
release: 1.82.0-nightly
commit-hash: 8f40fc59fb0c8df91c97405785197f3c630304ea
commit-date: 2024-08-21
host: aarch64-apple-darwin
libgit2: 1.8.1 (sys:0.19.0 vendored)
libcurl: 8.7.1 (sys:0.4.74+curl-8.9.0 system ssl:(SecureTransport) LibreSSL/3.3.6)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Mac OS 15.0.0 [64-bit]
```
