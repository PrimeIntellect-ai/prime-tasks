Some of Rust proc-macro tests cause compiler to crash
Failing tests:
- tests/ui/proc-macro/meta-macro.rs
- tests/ui/proc-macro/meta-macro-hygiene.rs

They both crash when calling `free` when rustc is linked with wild:
```
--- stdout -------------------------------
Def site: /home/mateusz/Projects/rust/tests/ui/proc-macro/auxiliary/make-macro.rs:7:9: 7:56 (#3)
Input: TokenStream []
Respanned: TokenStream []
------------------------------------------
--- stderr -------------------------------
free(): invalid pointer
------------------------------------------
```
It's not a crash in the test binary, but a crash inside stage1 rustc executable, likely making the debugging harder.

### Additional contract requirements

- When linking a shared object whose TLS segment contains only zero-initialised (TBSS) data and no initialised (TDATA) data, the TLS variables in that object must be placed at the correct offsets so that they can be read and written correctly at runtime.
