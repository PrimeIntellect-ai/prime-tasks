Constructing a negative `LitInt` panics as unreachable
Minimal example:

```rust
use syn::LitInt;
use proc_macro2::Span;

fn main() {
    LitInt::new("-1", Span::call_site());
}
```

`cargo run` backtrace:

```text
thread 'main' panicked at 'internal error: entered unreachable code', /home/jhpratt/.cargo/registry/src/github.com-1ecc6299db9ec823/syn-1.0.13/src/lit.rs:1379:18
stack backtrace:
   0: backtrace::backtrace::libunwind::trace
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.40/src/backtrace/libunwind.rs:88
   1: backtrace::backtrace::trace_unsynchronized
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.40/src/backtrace/mod.rs:66
   2: std::sys_common::backtrace::_print_fmt
             at src/libstd/sys_common/backtrace.rs:84
   3: <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt
             at src/libstd/sys_common/backtrace.rs:61
   4: core::fmt::write
             at src/libcore/fmt/mod.rs:1025
   5: std::io::Write::write_fmt
             at src/libstd/io/mod.rs:1426
   6: std::sys_common::backtrace::_print
             at src/libstd/sys_common/backtrace.rs:65
   7: std::sys_common::backtrace::print
             at src/libstd/sys_common/backtrace.rs:50
   8: std::panicking::default_hook::{{closure}}
             at src/libstd/panicking.rs:193
   9: std::panicking::default_hook
             at src/libstd/panicking.rs:210
  10: std::panicking::rust_panic_with_hook
             at src/libstd/panicking.rs:475
  11: std::panicking::begin_panic
             at /rustc/0de96d37fbcc54978458c18f5067cd9817669bc8/src/libstd/panicking.rs:404
  12: syn::lit::value::to_literal
             at /home/jhpratt/.cargo/registry/src/github.com-1ecc6299db9ec823/syn-1.0.13/src/lit.rs:1379
  13: syn::lit::LitInt::new
             at /home/jhpratt/.cargo/registry/src/github.com-1ecc6299db9ec823/syn-1.0.13/src/lit.rs:407
  14: tmp::main
             at src/main.rs:5
  15: std::rt::lang_start::{{closure}}
             at /rustc/0de96d37fbcc54978458c18f5067cd9817669bc8/src/libstd/rt.rs:67
  16: std::rt::lang_start_internal::{{closure}}
             at src/libstd/rt.rs:52
  17: std::panicking::try::do_call
             at src/libstd/panicking.rs:292
  18: __rust_maybe_catch_panic
             at src/libpanic_unwind/lib.rs:78
  19: std::panicking::try
             at src/libstd/panicking.rs:270
  20: std::panic::catch_unwind
             at src/libstd/panic.rs:394
  21: std::rt::lang_start_internal
             at src/libstd/rt.rs:51
  22: std::rt::lang_start
             at /rustc/0de96d37fbcc54978458c18f5067cd9817669bc8/src/libstd/rt.rs:67
  23: main
  24: __libc_start_main
  25: _start
```

Versions:
- syn: 1.0.13
- proc-macro2: 1.0.7

After taking a quick look at `lit.rs`, it looks like this should work. At the minimum, it definitely shouldn't reach an "unreachable!()" declaration.

I ran into this in real-world code, so it's certainly not unheard of to want to do something like this.

### Additional contract requirements

- The constructed literal must preserve the sign and suffix in its textual
  representation. For example, `LitInt::new("-1", Span::call_site()).to_string()`
  is `"-1"`, and `LitInt::new("-1i8", Span::call_site()).to_string()` is `"-1i8"`.
