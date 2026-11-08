Assertion error in unification
> equating two type variables, both of which have known types: Tuple([]) and Tuple([])


backtrace:

```
thread '<unnamed>' panicked at 'equating two type variables, both of which have known types: Tuple([]) and Tuple([])', crates/ra_hir/src/ty.rs:93:67
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
stack backtrace:
   0: std::sys::unix::backtrace::tracing::imp::unwind_backtrace
             at libstd/sys/unix/backtrace/tracing/gcc_s.rs:49
   1: std::sys_common::backtrace::print
             at libstd/sys_common/backtrace.rs:71
             at libstd/sys_common/backtrace.rs:59
   2: std::panicking::default_hook::{{closure}}
             at libstd/panicking.rs:211
   3: std::panicking::default_hook
             at libstd/panicking.rs:227
   4: std::panicking::rust_panic_with_hook
             at libstd/panicking.rs:476
   5: std::panicking::continue_panic_fmt
             at libstd/panicking.rs:390
   6: std::panicking::begin_panic_fmt
             at libstd/panicking.rs:345
   7: <ra_hir::ty::TypeVarValue as ena::unify::UnifyValue>::unify_values
             at crates/ra_hir/src/ty.rs:93
   8: <ena::unify::UnificationTable<S>>::union_value
             at /home/matklad/.cargo/registry/src/github.com-1ecc6299db9ec823/ena-0.11.0/src/unify/mod.rs:493
             at /home/matklad/.cargo/registry/src/github.com-1ecc6299db9ec823/ena-0.11.0/src/unify/mod.rs:441
   9: <ra_hir::ty::InferenceContext<'a, D>>::unify
             at ./crates/ra_hir/src/ty.rs:697
  10: <ra_hir::ty::InferenceContext<'a, D>>::infer_expr
             at ./crates/ra_hir/src/ty.rs:983
  11: ra_hir::ty::infer
             at ./crates/ra_hir/src/ty.rs:1047
             at ./crates/ra_hir/src/ty.rs:1067
  12: <salsa::runtime::Runtime<DB>>::execute_query_implementation
             at ./<::salsa::query_group macros>:58
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/derived.rs:346
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/runtime.rs:310
  13: <salsa::derived::DerivedStorage<DB, Q, MP>>::read_upgrade
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/derived.rs:339
  14: <salsa::derived::DerivedStorage<DB, Q, MP> as salsa::plumbing::QueryStorageOps<DB, Q>>::try_fetch
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/derived.rs:268
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/derived.rs:673
  15: <salsa::QueryTable<'_, DB, Q>>::get
             at /home/matklad/.cargo/git/checkouts/salsa-3f2277f1661c3426/88313c8/src/lib.rs:378
  16: ra_ide_api::completion::complete_dot::complete_dot
             at ./<::salsa::query_group macros>:25
             at ./crates/ra_hir/src/code_model_api.rs:253
             at crates/ra_ide_api/src/completion/complete_dot.rs:12
  17: ra_ide_api::completion::completions
             at crates/ra_ide_api/src/completion.rs:62
  18: std::panicking::try::do_call
             at crates/ra_ide_api/src/lib.rs:487
             at ./crates/ra_db/src/lib.rs:34
             at libstd/panicking.rs:310
  19: __rust_maybe_catch_panic
             at libpanic_unwind/lib.rs:102
  20: ra_db::BaseDatabase::catch_canceled
             at libstd/panicking.rs:289
             at libstd/panic.rs:392
             at ./crates/ra_db/src/lib.rs:34
  21: ra_ide_api::Analysis::completions
             at crates/ra_ide_api/src/lib.rs:485
  22: ra_lsp_server::main_loop::handlers::handle_completion
             at crates/ra_lsp_server/src/main_loop/handlers.rs:430
  23: <F as threadpool::FnBox>::call_box
             at crates/ra_lsp_server/src/main_loop.rs:421
             at /home/matklad/.cargo/registry/src/github.com-1ecc6299db9ec823/threadpool-1.7.1/src/lib.rs:95
```

cc @flodiebold

### Additional contract requirements

Type inference for the reported `let x = if true {};` expression must complete without panicking with the assertion that two type variables with known types are being equated.
