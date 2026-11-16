Creating environment variable with dynamic name panics
```
> let x = "FOO"

> let-env $x = "foo"
thread 'main' panicked at 'internal error: missing variable', crates/nu-command/src/env/let_env.rs:38:14
stack backtrace:
   0: rust_begin_unwind
             at /rustc/db9d1b20bba1968c1ec1fc49616d4742c1725b4b/library/std/src/panicking.rs:498:5
   1: core::panicking::panic_fmt
             at /rustc/db9d1b20bba1968c1ec1fc49616d4742c1725b4b/library/core/src/panicking.rs:107:14
   2: core::panicking::panic_display
             at /rustc/db9d1b20bba1968c1ec1fc49616d4742c1725b4b/library/core/src/panicking.rs:63:5
   3: core::option::expect_failed
             at /rustc/db9d1b20bba1968c1ec1fc49616d4742c1725b4b/library/core/src/option.rs:1637:5
   4: <nu_command::env::let_env::LetEnv as nu_protocol::engine::command::Command>::run
   5: nu_engine::eval::eval_call
   6: nu_engine::eval::eval_expression_with_input
   7: nu_engine::eval::eval_block
   8: nu::utils::eval_source
   9: nu::repl::evaluate
  10: nu::main
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```

This works fine in Nushell
