Panic in SLG solver: clear_strands_after_cycle invoked on strand in table without a selected subgoal
The following test case (extracted from `liballoc`) causes the SGL solve to panic (the recursive solver handles this just fine)

```rust
#[test]
fn to_owned_rc_impl() {
    test! {
        program {
            #[non_enumerable]
            #[lang(sized)]
            trait Sized { }
            trait From<T> where T: Sized {
            }
            trait ToOwned {
                type Owned;
            }

            impl<T> ToOwned for [T] where T: Sized {
                type Owned = Vec<T>;
            }

            struct Rc<T> { }

            struct Vec<T> where T: Sized {}
            struct Cow<'x, T> where T: ToOwned {}

            impl<'a, T> From<&'a [T]> for Rc<[T]> where T: Sized {}
            impl<T> From<Vec<T>> for Rc<[T]> where T: Sized {}
            impl<'a, B> From<Cow<'a, B>> for Rc<B>
            where
                B: ToOwned,
                Rc<B>: From<&'a B>,
                Rc<B>: From<<B as ToOwned>::Owned>
            {
            }
        }

        goal {
            exists<S, T> {
                Rc<S>: From<T>
            }
        } yields {
            "Ambiguous; no inference guidance"
        }
    }
}
```

<details>

<summary>Output and backtrace</summary>

```text
running 1 test
program {
    # [non_enumerable] # [lang(sized)] trait Sized { } trait From < T > where
    T : Sized { } trait ToOwned { type Owned ; } impl < T > ToOwned for [T]
    where T : Sized { type Owned = Vec < T > ; } struct Rc < T > { } struct
    Vec < T > where T : Sized { } struct Cow < 'x, T > where T : ToOwned { }
    impl < 'a, T > From < & 'a [T] > for Rc < [T] > where T : Sized { } impl <
    T > From < Vec < T >> for Rc < [T] > where T : Sized { } impl < 'a, B
    > From < Cow < 'a, B >> for Rc < B > where B : ToOwned, Rc < B > : From <
    & 'a B >, Rc < B > : From << B as ToOwned > :: Owned > { }
}
----------------------------------------------------------------------
goal { exists < S, T > { Rc < S > : From < T > } }
using solver: SLG { max_size: 10, expected_answers: None }
thread 'test::existential_types::to_owned_rc_impl' panicked at 'clear_strands_after_cycle invoked on strand in table without a selected subgoal: Canonical { value: ExClause { subst: [?0 := {slice}<^0.0>], ambiguous: true, constraints: [], subgoals: [], delayed_subgoals: [], answer_time: TimeStamp { clock: 0 }, floundered_subgoals: [FlounderedSubgoal { floundered_literal: Positive(InEnvironment { environment: Env([]), goal: ForAll<> { Implemented(^1.0: Sized) } }), floundered_time: TimeStamp { clock: 0 } }, FlounderedSubgoal { floundered_literal: Positive(InEnvironment { environment: Env([]), goal: AliasEq(<{slice}<^0.0> as ToOwned>::Owned = Vec<^0.0>) }), floundered_time: TimeStamp { clock: 0 } }] }, binders: [U0 with kind type] }', /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/macros.rs:16:9
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
  13: chalk_engine::logic::SolveState<I,C,CO>::clear_strands_after_cycle::{{closure}}
             at /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/macros.rs:16
  14: core::option::Option<T>::unwrap_or_else
             at /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libcore/option.rs:428
  15: chalk_engine::logic::SolveState<I,C,CO>::clear_strands_after_cycle
             at ./chalk-engine/src/logic.rs:1257
  16: chalk_engine::logic::SolveState<I,C,CO>::clear_strands_after_cycle
             at ./chalk-engine/src/logic.rs:1267
  17: chalk_engine::logic::SolveState<I,C,CO>::on_no_strands_left
             at ./chalk-engine/src/logic.rs:1175
  18: chalk_engine::logic::SolveState<I,C,CO>::ensure_root_answer
             at ./chalk-engine/src/logic.rs:528
  19: chalk_engine::logic::<impl chalk_engine::forest::Forest<I,C>>::root_answer
             at ./chalk-engine/src/logic.rs:93
  20: <chalk_engine::forest::ForestSolver<I,C,CO> as chalk_engine::context::AnswerStream<I>>::peek_answer
             at ./chalk-engine/src/forest.rs:74
  21: <chalk_engine::forest::ForestSolver<I,C,CO> as chalk_engine::context::AnswerStream<I>>::next_answer
             at ./chalk-engine/src/forest.rs:113
  22: <chalk_engine::slg::SlgContextOps<I> as chalk_engine::slg::aggregate::AggregateOps<I>>::make_solution
             at ./chalk-engine/src/slg/aggregate.rs:34
  23: <chalk_engine::solve::SLGSolver<I> as chalk_solve::solve::Solver<I>>::solve
             at ./chalk-engine/src/solve.rs:40
  24: <chalk_integration::SolverImpl as chalk_solve::solve::Solver<chalk_integration::interner::ChalkIr>>::solve
             at chalk-integration/src/lib.rs:102
  25: chalk_integration::db::ChalkDatabase::solve
             at chalk-integration/src/db.rs:60
  26: lib::test::solve_goal::{{closure}}::{{closure}}
             at tests/test/mod.rs:258
  27: chalk_integration::tls::set_current_program::{{closure}}
             at ./chalk-integration/src/tls.rs:160
  28: std::thread::local::LocalKey<T>::try_with
             at /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/thread/local.rs:263
  29: std::thread::local::LocalKey<T>::with
             at /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libstd/thread/local.rs:239
  30: chalk_integration::tls::set_current_program
             at ./chalk-integration/src/tls.rs:158
  31: lib::test::solve_goal::{{closure}}
             at tests/test/mod.rs:244
  32: tracing_core::dispatcher::with_default
             at /home/matthew/.cargo/registry/src/github.com-1ecc6299db9ec823/tracing-core-0.1.10/src/dispatcher.rs:222
  33: tracing::subscriber::with_default
             at /home/matthew/.cargo/registry/src/github.com-1ecc6299db9ec823/tracing-0.1.15/src/subscriber.rs:24
  34: chalk_solve::logging::with_tracing_logs
             at ./chalk-solve/src/logging.rs:11
  35: lib::test::solve_goal
             at tests/test/mod.rs:219
  36: lib::test::existential_types::to_owned_rc_impl
             at tests/test/existential_types.rs:446
  37: lib::test::existential_types::to_owned_rc_impl::{{closure}}
             at tests/test/existential_types.rs:445
  38: core::ops::function::FnOnce::call_once
             at /home/matthew/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/src/libcore/ops/function.rs:232
  39: <alloc::boxed::Box<F> as core::ops::function::FnOnce<A>>::call_once
             at /rustc/c7087fe00d2ba919df1d813c040a5d47e43b0fe7/src/liballoc/boxed.rs:1008
  40: <std::panic::AssertUnwindSafe<F> as core::ops::function::FnOnce<()>>::call_once
             at /rustc/c7087fe00d2ba919df1d813c040a5d47e43b0fe7/src/libstd/panic.rs:318
  41: std::panicking::try::do_call
             at /rustc/c7087fe00d2ba919df1d813c040a5d47e43b0fe7/src/libstd/panicking.rs:331
  42: std::panicking::try
             at /rustc/c7087fe00d2ba919df1d813c040a5d47e43b0fe7/src/libstd/panicking.rs:274
  43: std::panic::catch_unwind
             at /rustc/c7087fe00d2ba919df1d813c040a5d47e43b0fe7/src/libstd/panic.rs:394
  44: test::run_test_in_process
             at src/libtest/lib.rs:541
  45: test::run_test::run_test_inner::{{closure}}
             at src/libtest/lib.rs:450
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
test test::existential_types::to_owned_rc_impl ... FAILED

failures:

failures:
    test::existential_types::to_owned_rc_impl

test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 375 filtered out

error: test failed, to rerun pass '-p chalk --test lib'
The terminal process "/usr/bin/fish '-c', 'cargo test --package chalk --test lib -- test::existential_types::to_owned_rc_impl --exact --nocapture'" terminated with exit code: 101.
```

</details>
