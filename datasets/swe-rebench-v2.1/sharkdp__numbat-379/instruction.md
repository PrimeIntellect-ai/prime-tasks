Unexpected panic when using datetime formatter
While experimenting with datetime formatting, I accidentally entered a bad format and caused a panic. Here it is with standard backtrace:

```
>>> format_datetime("%Y-%m-%dT%H%:M", now())
thread 'main' panicked at /rustc/07dca489ac2d933c78d3c5158e3f43beefeb02ce/library/alloc/src/string.rs:2611:14:
a Display implementation returned an error unexpectedly: Error
stack backtrace:
   0: rust_begin_unwind
             at /rustc/07dca489ac2d933c78d3c5158e3f43beefeb02ce/library/std/src/panicking.rs:645:5
   1: core::panicking::panic_fmt
             at /rustc/07dca489ac2d933c78d3c5158e3f43beefeb02ce/library/core/src/panicking.rs:72:14
   2: core::result::unwrap_failed
             at /rustc/07dca489ac2d933c78d3c5158e3f43beefeb02ce/library/core/src/result.rs:1649:5
   3: numbat::ffi::format_datetime
   4: numbat::vm::Vm::run_without_cleanup
   5: numbat::vm::Vm::run
   6: <numbat::bytecode_interpreter::BytecodeInterpreter as numbat::interpreter::Interpreter>::interpret_statements
   7: numbat::Context::interpret_with_settings
   8: numbat::Cli::parse_and_evaluate
   9: numbat::Cli::run
  10: numbat::main
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```

This should probably not leak (and certainly shouldn't crash the program). I also saw some unrelated panics in WASM, which is more annoying to debug because you can't easily see the backtrace. 🙂 Unfortunately, I didn't note down what caused them.
