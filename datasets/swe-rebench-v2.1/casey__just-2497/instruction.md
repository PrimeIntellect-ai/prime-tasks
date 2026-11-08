Feature request: add attribute `openbsd`
Trying to compile a recent version of [optimism](https://github.com/ethereum-optimism/optimism/blob/op-node/v1.10.0/CONTRIBUTING.md#development-quick-start) on OpenBSD/adJ 7.6beta1 I found that it uses `just`.

On OpenBSD/adJ 7.6beta1, it was straightforward to compile `just` and run its tests except for two tests that depend on attributes for the supported platforms (`linux`, `windows`, `macos`):
```sh
 % uname -a
OpenBSD selah.pasosdeJesus.org 7.6 APRENDIENDODEJESUS.MP#1 amd64
% rustc --version
rustc 1.81.0 (eeb90cda1 2024-09-04) (built from a source tarball)
% git clone git@github.com:casey/just.git/
...
% cargo build
...
% cargo install --path .
...
% RUST_BACKTRACE=1 LANG=POSIX cargo test
...

failures:

---- attributes::multiple_attributes_one_line stdout ----
Bad stderr: Diff < left / right > :
<error: Justfile contains no recipes.
>exit 1


thread 'attributes::multiple_attributes_one_line' panicked at tests/attributes.rs:59:6:
Output mismatch.
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: integration::test::Test::run
             at ./tests/test.rs:293:7
   3: integration::attributes::multiple_attributes_one_line
             at ./tests/attributes.rs:48:3
   4: integration::attributes::multiple_attributes_one_line::{{closure}}
             at ./tests/attributes.rs:47:34
   5: core::ops::function::FnOnce::call_once
             at /usr/obj/ports/rust-1.81.0/rustc-1.81.0-src/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.

---- os_attributes::os stdout ----
thread 'os_attributes::os' panicked at tests/os_attributes.rs:59:7:
unexpected os family
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: integration::os_attributes::os
             at ./tests/os_attributes.rs:59:7
   3: integration::os_attributes::os::{{closure}}
             at ./tests/os_attributes.rs:35:8
   4: core::ops::function::FnOnce::call_once
             at /usr/obj/ports/rust-1.81.0/rustc-1.81.0-src/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.


failures:
    attributes::multiple_attributes_one_line
    os_attributes::os

test result: FAILED. 850 passed; 2 failed; 7 ignored; 0 measured; 0 filtered out; finished in 20.05s

error: test failed, to rerun pass `--test integration`
```

Since Rust supports OpenBSD:  <https://doc.rust-lang.org/rustc/platform-support/openbsd.html>, IMHO it makes sense to add initial support for OpenBSD in `just` by adding an attribute `openbsd` to enable recipes on OpenBSD.
