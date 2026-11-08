Stripping `extern "Rust"` from functions
Rustfmt currently strips `extern "Rust"` from function signatures. e.g formatting `extern "Rust" fn foo() {}` to `fn foo() {}`. This seems to be intentional from the current code.

The problem here is this essentially deletes documentation from the code. Given a function such as:
```rust
#[no_mangle]
extern "Rust" fn foo() { /* do stuff */ }
```
With the ABI explicitly added here, it's clear that the odd ABI choice is intentional. Without the explicit ABI, it's unclear whether the choice was intentional, or an ABI was forgotten (e.g. `extern "C"`).

Can't find anything relevant from the style guide about this removal.

### Additional contract requirements

When formatting a function whose source explicitly specifies `extern "Rust"`, retain that explicit ABI in the formatted signature.
