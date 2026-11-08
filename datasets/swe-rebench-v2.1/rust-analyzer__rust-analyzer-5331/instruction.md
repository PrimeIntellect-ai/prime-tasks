`std::iter::repeat` blows analyzer apart
rust-analyzer version: unreleased (c8557b9)

The following code breaks everything: hover, completion, and even highlighting.
```rust
fn test() {
    let steps = [
        (0.,  0.),
    ];

    let mut weights = Vec::from_iter(
        std::iter::repeat    // <---  Comment this line to fix things
        (
            steps
                .iter()
                .map(|&(_, w)| w) //    <-- or this one
                .take(12 + 24)
        )
    );

    (1..10).map(|index| weights.iter_mut());
}
```

```
thread '<unnamed>' panicked at 'assertion failed: `(left == right)`
  left: `^1`,
 right: `^0`', /home/korvin/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/macros.rs:16:9
stack backtrace:
   0: backtrace::backtrace::libunwind::trace
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/libunwind.rs:86
   1: backtrace::backtrace::trace_unsynchronized
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/mod.rs:66
   2: std::sys_common::backtrace::_print_fmt
             at src/libstd/sys_common/backtrace.rs:78
   3: <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt
             at src/libstd/sys_common/backtrace.rs:59
   4: core::fmt::write
             at src/libcore/fmt/mod.rs:1069
   5: std::io::Write::write_fmt
             at src/libstd/io/mod.rs:1504
   6: std::sys_common::backtrace::_print
             at src/libstd/sys_common/backtrace.rs:62
   7: std::sys_common::backtrace::print
             at src/libstd/sys_common/backtrace.rs:49
   8: std::panicking::default_hook::{{closure}}
             at src/libstd/panicking.rs:198
   9: std::panicking::default_hook
             at src/libstd/panicking.rs:218
  10: std::panicking::rust_panic_with_hook
             at src/libstd/panicking.rs:511
  11: rust_begin_unwind
             at src/libstd/panicking.rs:419
  12: std::panicking::begin_panic_fmt
             at src/libstd/panicking.rs:373
  13: <&chalk_ir::SubstFolder<I> as chalk_ir::fold::Folder<I>>::fold_free_var_ty
  14: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  15: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  16: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  17: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  18: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  19: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  20: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  21: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  22: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  23: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  24: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  25: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  26: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  27: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  28: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  29: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  30: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  31: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  32: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  33: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  34: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  35: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  36: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  37: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  38: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  39: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  40: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  41: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  42: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  43: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  44: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_WhereClause::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::WhereClause<I>>::fold_with
  45: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_DomainGoal::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::DomainGoal<I>>::fold_with
  46: chalk_ir::Substitution<I>::apply
  47: chalk_solve::infer::InferenceTable<I>::from_canonical
  48: chalk_solve::recursive::fulfill::Fulfill<I>::new
  49: chalk_solve::recursive::Solver<I>::solve_via_implication
  50: chalk_solve::recursive::Solver<I>::solve_goal
  51: chalk_solve::recursive::Solver<I>::solve_root_goal
  52: ra_hir_ty::traits::trait_solve_query
  53: salsa::runtime::Runtime<DB>::execute_query_implementation
  54: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  55: salsa::derived::slot::Slot<DB,Q,MP>::read
  56: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  57: salsa::QueryTable<DB,Q>::get
  58: <T as ra_hir_ty::db::HirDatabase>::trait_solve
  59: ra_hir_ty::autoderef::deref
  60: <core::iter::adapters::Take<I> as core::iter::traits::iterator::Iterator>::next
  61: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  62: ra_hir_ty::method_resolution::autoderef_method_receiver
  63: ra_hir_ty::method_resolution::iterate_method_candidates
  64: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  65: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  66: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  67: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  68: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  69: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::check_call_arguments
  70: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  71: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  72: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr
  73: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  74: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  75: ra_hir_ty::infer::infer_query
  76: salsa::runtime::Runtime<DB>::execute_query_implementation
  77: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  78: salsa::derived::slot::Slot<DB,Q,MP>::read
  79: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  80: ra_hir_ty::db::infer_wait
  81: ra_hir::source_analyzer::SourceAnalyzer::new_for_body
  82: ra_hir::semantics::Semantics<DB>::analyze2
  83: ra_hir::semantics::Semantics<DB>::descend_into_macros
  84: ra_ide::hover::hover
  85: std::panicking::try
  86: ra_ide::Analysis::hover
  87: rust_analyzer::main_loop::handlers::handle_hover
  88: <F as threadpool::FnBox>::call_box
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
thread '<unnamed>' panicked at 'assertion failed: `(left == right)`
  left: `^1`,
 right: `^0`', /home/korvin/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/macros.rs:16:9
stack backtrace:
   0: backtrace::backtrace::libunwind::trace
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/libunwind.rs:86
   1: backtrace::backtrace::trace_unsynchronized
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/mod.rs:66
   2: std::sys_common::backtrace::_print_fmt
             at src/libstd/sys_common/backtrace.rs:78
   3: <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt
             at src/libstd/sys_common/backtrace.rs:59
   4: core::fmt::write
             at src/libcore/fmt/mod.rs:1069
   5: std::io::Write::write_fmt
             at src/libstd/io/mod.rs:1504
   6: std::sys_common::backtrace::_print
             at src/libstd/sys_common/backtrace.rs:62
   7: std::sys_common::backtrace::print
             at src/libstd/sys_common/backtrace.rs:49
   8: std::panicking::default_hook::{{closure}}
             at src/libstd/panicking.rs:198
   9: std::panicking::default_hook
             at src/libstd/panicking.rs:218
  10: std::panicking::rust_panic_with_hook
             at src/libstd/panicking.rs:511
  11: rust_begin_unwind
             at src/libstd/panicking.rs:419
  12: std::panicking::begin_panic_fmt
             at src/libstd/panicking.rs:373
  13: <&chalk_ir::SubstFolder<I> as chalk_ir::fold::Folder<I>>::fold_free_var_ty
  14: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  15: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  16: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  17: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  18: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  19: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  20: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  21: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  22: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  23: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  24: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  25: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  26: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  27: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  28: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  29: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  30: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  31: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  32: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  33: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  34: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  35: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  36: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  37: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  38: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  39: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  40: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  41: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  42: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  43: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  44: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_WhereClause::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::WhereClause<I>>::fold_with
  45: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_DomainGoal::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::DomainGoal<I>>::fold_with
  46: chalk_ir::Substitution<I>::apply
  47: chalk_solve::infer::InferenceTable<I>::from_canonical
  48: chalk_solve::recursive::fulfill::Fulfill<I>::new
  49: chalk_solve::recursive::Solver<I>::solve_via_implication
  50: chalk_solve::recursive::Solver<I>::solve_goal
  51: chalk_solve::recursive::Solver<I>::solve_root_goal
  52: ra_hir_ty::traits::trait_solve_query
  53: salsa::runtime::Runtime<DB>::execute_query_implementation
  54: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  55: salsa::derived::slot::Slot<DB,Q,MP>::read
  56: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  57: salsa::QueryTable<DB,Q>::get
  58: <T as ra_hir_ty::db::HirDatabase>::trait_solve
  59: ra_hir_ty::autoderef::deref
  60: <core::iter::adapters::Take<I> as core::iter::traits::iterator::Iterator>::next
  61: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  62: ra_hir_ty::method_resolution::autoderef_method_receiver
  63: ra_hir_ty::method_resolution::iterate_method_candidates
  64: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  65: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  66: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  67: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  68: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  69: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::check_call_arguments
  70: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  71: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  72: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr
  73: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  74: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  75: ra_hir_ty::infer::infer_query
  76: salsa::runtime::Runtime<DB>::execute_query_implementation
  77: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  78: salsa::derived::slot::Slot<DB,Q,MP>::read
  79: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  80: ra_hir_ty::db::infer_wait
  81: ra_hir::source_analyzer::SourceAnalyzer::new_for_body
  82: ra_hir::semantics::Semantics<DB>::analyze2
  83: ra_hir::semantics::Semantics<DB>::descend_into_macros
  84: rowan::utility_types::TokenAtOffset<T>::map
  85: ra_hir::semantics::Semantics<DB>::find_node_at_offset_with_descend
  86: ra_ide::references::find_all_refs
  87: std::panicking::try
  88: ra_db::CheckCanceled::catch_canceled
  89: ra_ide::Analysis::find_all_refs
  90: rust_analyzer::main_loop::handlers::handle_document_highlight
  91: <F as threadpool::FnBox>::call_box
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
thread '<unnamed>' panicked at 'assertion failed: `(left == right)`
  left: `^1`,
 right: `^0`', /home/korvin/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/macros.rs:16:9
stack backtrace:
   0: backtrace::backtrace::libunwind::trace
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/libunwind.rs:86
   1: backtrace::backtrace::trace_unsynchronized
             at /cargo/registry/src/github.com-1ecc6299db9ec823/backtrace-0.3.46/src/backtrace/mod.rs:66
   2: std::sys_common::backtrace::_print_fmt
             at src/libstd/sys_common/backtrace.rs:78
   3: <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt
             at src/libstd/sys_common/backtrace.rs:59
   4: core::fmt::write
             at src/libcore/fmt/mod.rs:1069
   5: std::io::Write::write_fmt
             at src/libstd/io/mod.rs:1504
   6: std::sys_common::backtrace::_print
             at src/libstd/sys_common/backtrace.rs:62
   7: std::sys_common::backtrace::print
             at src/libstd/sys_common/backtrace.rs:49
   8: std::panicking::default_hook::{{closure}}
             at src/libstd/panicking.rs:198
   9: std::panicking::default_hook
             at src/libstd/panicking.rs:218
  10: std::panicking::rust_panic_with_hook
             at src/libstd/panicking.rs:511
  11: rust_begin_unwind
             at src/libstd/panicking.rs:419
  12: std::panicking::begin_panic_fmt
             at src/libstd/panicking.rs:373
  13: <&chalk_ir::SubstFolder<I> as chalk_ir::fold::Folder<I>>::fold_free_var_ty
  14: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  15: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  16: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  17: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  18: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  19: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  20: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  21: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  22: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  23: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  24: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  25: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  26: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  27: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  28: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  29: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  30: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  31: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  32: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  33: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  34: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  35: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  36: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  37: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  38: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  39: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  40: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  41: <chalk_ir::Ty<I> as chalk_ir::fold::SuperFold<I,TI>>::super_fold_with
  42: chalk_ir::fold::boring_impls::<impl chalk_ir::fold::Fold<I,TI> for chalk_ir::GenericArg<I>>::fold_with
  43: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  44: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_WhereClause::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::WhereClause<I>>::fold_with
  45: chalk_ir::_DERIVE_chalk_ir_fold_Fold_I_TI_FOR_DomainGoal::<impl chalk_ir::fold::Fold<I,_TI> for chalk_ir::DomainGoal<I>>::fold_with
  46: chalk_ir::Substitution<I>::apply
  47: chalk_solve::infer::InferenceTable<I>::from_canonical
  48: chalk_solve::recursive::fulfill::Fulfill<I>::new
  49: chalk_solve::recursive::Solver<I>::solve_via_implication
  50: chalk_solve::recursive::Solver<I>::solve_goal
  51: chalk_solve::recursive::Solver<I>::solve_root_goal
  52: ra_hir_ty::traits::trait_solve_query
  53: salsa::runtime::Runtime<DB>::execute_query_implementation
  54: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  55: salsa::derived::slot::Slot<DB,Q,MP>::read
  56: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  57: salsa::QueryTable<DB,Q>::get
  58: <T as ra_hir_ty::db::HirDatabase>::trait_solve
  59: ra_hir_ty::autoderef::deref
  60: <core::iter::adapters::Take<I> as core::iter::traits::iterator::Iterator>::next
  61: <alloc::vec::Vec<T> as alloc::vec::SpecExtend<T,I>>::from_iter
  62: ra_hir_ty::method_resolution::autoderef_method_receiver
  63: ra_hir_ty::method_resolution::iterate_method_candidates
  64: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  65: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  66: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  67: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  68: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  69: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::check_call_arguments
  70: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_method_call
  71: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  72: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr
  73: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_inner
  74: ra_hir_ty::infer::expr::<impl ra_hir_ty::infer::InferenceContext>::infer_expr_coerce
  75: ra_hir_ty::infer::infer_query
  76: salsa::runtime::Runtime<DB>::execute_query_implementation
  77: salsa::derived::slot::Slot<DB,Q,MP>::read_upgrade
  78: salsa::derived::slot::Slot<DB,Q,MP>::read
  79: <salsa::derived::DerivedStorage<DB,Q,MP> as salsa::plumbing::QueryStorageOps<DB,Q>>::try_fetch
  80: ra_hir_ty::db::infer_wait
  81: ra_hir::code_model::Function::diagnostics
  82: ra_hir::code_model::Module::diagnostics
  83: ra_ide::diagnostics::diagnostics
  84: std::panicking::try
  85: ra_ide::Analysis::diagnostics
  86: rust_analyzer::main_loop::handlers::handle_code_action
  87: <F as threadpool::FnBox>::call_box
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```
