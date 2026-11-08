ICE: unreachable `src/tools/rustfmt/src/expr.rs:407:13`
```rust

fn main() {
    println!("{}", builtin # offset_of(A, 0. 1.1.1));
}

```

```
thread 'main' panicked at src/tools/rustfmt/src/expr.rs:407:13:
internal error: entered unreachable code
stack backtrace:
   0:     0x7f5d061634ec - std::backtrace_rs::backtrace::libunwind::trace::h735859f22ae1ae42
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/../../backtrace/src/backtrace/libunwind.rs:93:5
   1:     0x7f5d061634ec - std::backtrace_rs::backtrace::trace_unsynchronized::hf2010d7ee6f90d09
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/../../backtrace/src/backtrace/mod.rs:66:5
   2:     0x7f5d061634ec - std::sys_common::backtrace::_print_fmt::h41f140d22a480669
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/sys_common/backtrace.rs:67:5
   3:     0x7f5d061634ec - <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt::hc0cf8f562aa74991
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/sys_common/backtrace.rs:44:22
   4:     0x7f5d061c8d7c - core::fmt::rt::Argument::fmt::h45214d1bb1360468
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/core/src/fmt/rt.rs:138:9
   5:     0x7f5d061c8d7c - core::fmt::write::h0cf0d88bfa21782e
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/core/src/fmt/mod.rs:1094:21
   6:     0x7f5d06155e8e - std::io::Write::write_fmt::h0d843d62f88873a3
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/io/mod.rs:1714:15
   7:     0x7f5d061632d4 - std::sys_common::backtrace::_print::h214e31acf5fce41f
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/sys_common/backtrace.rs:47:5
   8:     0x7f5d061632d4 - std::sys_common::backtrace::print::h0be3a8355cde20c1
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/sys_common/backtrace.rs:34:9
   9:     0x7f5d061663ca - std::panicking::panic_hook_with_disk_dump::{{closure}}::h14933742ebca4954
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:278:22
  10:     0x7f5d061660b7 - std::panicking::panic_hook_with_disk_dump::h934c976f93b38e49
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:312:9
  11:     0x7f5d093450e9 - <rustc_driver_impl[6be839844fedfd7f]::install_ice_hook::{closure#0} as core[6093bc177ae0b635]::ops::function::FnOnce<(&core[6093bc177ae0b635]::panic::panic_info::PanicInfo,)>>::call_once::{shim:vtable#0}
  12:     0x7f5d06166c70 - <alloc::boxed::Box<F,A> as core::ops::function::Fn<Args>>::call::h17a87ce95b5189e5
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/alloc/src/boxed.rs:2021:9
  13:     0x7f5d06166c70 - std::panicking::rust_panic_with_hook::h57165fef3c33fe3c
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:733:13
  14:     0x7f5d061669b1 - std::panicking::begin_panic_handler::{{closure}}::hd3d74044bc679432
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:619:13
  15:     0x7f5d06163a16 - std::sys_common::backtrace::__rust_end_short_backtrace::hb0880b96bb7f18bf
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/sys_common/backtrace.rs:170:18
  16:     0x7f5d06166742 - rust_begin_unwind
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:617:5
  17:     0x7f5d061c5183 - core::panicking::panic_fmt::h1328a2d38b9d4c22
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/core/src/panicking.rs:67:14
  18:     0x7f5d061c5213 - core::panicking::panic::h7c6960874348cf53
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/core/src/panicking.rs:117:5
  19:     0x55d6a0f22bd5 - rustfmt_nightly[6c3958c54b76f126]::expr::format_expr
  20:     0x55d6a0f3ede1 - <rustfmt_nightly[6c3958c54b76f126]::macros::MacroArg as rustfmt_nightly[6c3958c54b76f126]::rewrite::Rewrite>::rewrite
  21:     0x55d6a0e93fbe - <rustfmt_nightly[6c3958c54b76f126]::overflow::OverflowableItem as rustfmt_nightly[6c3958c54b76f126]::rewrite::Rewrite>::rewrite
  22:     0x55d6a0e97c79 - <rustfmt_nightly[6c3958c54b76f126]::overflow::Context>::rewrite_items
  23:     0x55d6a0e98cb4 - <rustfmt_nightly[6c3958c54b76f126]::overflow::Context>::rewrite
  24:     0x55d6a0e946bb - rustfmt_nightly[6c3958c54b76f126]::overflow::rewrite_with_parens::<rustfmt_nightly[6c3958c54b76f126]::macros::MacroArg, core[6093bc177ae0b635]::slice::iter::Iter<rustfmt_nightly[6c3958c54b76f126]::macros::MacroArg>>
  25:     0x55d6a0f40d4d - rustfmt_nightly[6c3958c54b76f126]::macros::rewrite_macro_inner
  26:     0x55d6a0f3ef2e - rustfmt_nightly[6c3958c54b76f126]::macros::rewrite_macro
  27:     0x55d6a0f8767c - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::visit_mac
  28:     0x55d6a0f8963b - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::walk_stmts
  29:     0x55d6a0f80687 - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::visit_block
  30:     0x55d6a0f83175 - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::visit_fn
  31:     0x55d6a0f83f41 - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::visit_item
  32:     0x55d6a0f7eebb - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::visit_items_with_reordering
  33:     0x55d6a0f89dcd - <rustfmt_nightly[6c3958c54b76f126]::visitor::FmtVisitor>::format_separate_mod
  34:     0x55d6a0e0bb5e - rustfmt_nightly[6c3958c54b76f126]::formatting::format_project::<rustfmt_nightly[6c3958c54b76f126]::Session<std[d5d19527909f28ae]::io::stdio::Stdout>>
  35:     0x55d6a0e065b2 - <scoped_tls[a4738d5243f410f]::ScopedKey<rustc_span[b474a88e3bf3a6a2]::SessionGlobals>>::with::<<rustfmt_nightly[6c3958c54b76f126]::Session<std[d5d19527909f28ae]::io::stdio::Stdout>>::format_input_inner::{closure#0}, core[6093bc177ae0b635]::result::Result<rustfmt_nightly[6c3958c54b76f126]::FormatReport, rustfmt_nightly[6c3958c54b76f126]::ErrorKind>>
  36:     0x55d6a0e03954 - <scoped_tls[a4738d5243f410f]::ScopedKey<rustc_span[b474a88e3bf3a6a2]::SessionGlobals>>::set::<rustc_span[b474a88e3bf3a6a2]::create_session_if_not_set_then<core[6093bc177ae0b635]::result::Result<rustfmt_nightly[6c3958c54b76f126]::FormatReport, rustfmt_nightly[6c3958c54b76f126]::ErrorKind>, <rustfmt_nightly[6c3958c54b76f126]::Session<std[d5d19527909f28ae]::io::stdio::Stdout>>::format_input_inner::{closure#0}>::{closure#0}, core[6093bc177ae0b635]::result::Result<rustfmt_nightly[6c3958c54b76f126]::FormatReport, rustfmt_nightly[6c3958c54b76f126]::ErrorKind>>
  37:     0x55d6a0e08a2f - <rustfmt_nightly[6c3958c54b76f126]::Session<std[d5d19527909f28ae]::io::stdio::Stdout>>::format_input_inner
  38:     0x55d6a0dfb5f7 - rustfmt[f304444a0a4ba634]::format_and_emit_report::<std[d5d19527909f28ae]::io::stdio::Stdout>
  39:     0x55d6a0e07fdb - <rustfmt_nightly[6c3958c54b76f126]::Session<std[d5d19527909f28ae]::io::stdio::Stdout>>::override_config::<rustfmt[f304444a0a4ba634]::format::{closure#0}, ()>
  40:     0x55d6a0dfa3d9 - rustfmt[f304444a0a4ba634]::execute
  41:     0x55d6a0df82b6 - rustfmt[f304444a0a4ba634]::main
  42:     0x55d6a0e088d3 - std[d5d19527909f28ae]::sys_common::backtrace::__rust_begin_short_backtrace::<fn(), ()>
  43:     0x55d6a0e0d1e9 - std[d5d19527909f28ae]::rt::lang_start::<()>::{closure#0}
  44:     0x7f5d0614635b - core::ops::function::impls::<impl core::ops::function::FnOnce<A> for &F>::call_once::hd625ab3f85f394d9
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/core/src/ops/function.rs:284:13
  45:     0x7f5d0614635b - std::panicking::try::do_call::hc2a2771195a00054
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:524:40
  46:     0x7f5d0614635b - std::panicking::try::h0a2a8257c216e1c6
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:488:19
  47:     0x7f5d0614635b - std::panic::catch_unwind::h0cd317587445f016
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panic.rs:142:14
  48:     0x7f5d0614635b - std::rt::lang_start_internal::{{closure}}::hf2376de1a4a8bfcd
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/rt.rs:148:48
  49:     0x7f5d0614635b - std::panicking::try::do_call::h5deb927a449cb0ab
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:524:40
  50:     0x7f5d0614635b - std::panicking::try::h6594b1002feb6499
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panicking.rs:488:19
  51:     0x7f5d0614635b - std::panic::catch_unwind::h2ea71858371b0c25
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/panic.rs:142:14
  52:     0x7f5d0614635b - std::rt::lang_start_internal::h03d2e46d47e99d1b
                               at /rustc/1b198b3a196442e14fb06978166ab46a4618d131/library/std/src/rt.rs:148:20
  53:     0x55d6a0dfc3b5 - main
  54:     0x7f5d05c27cd0 - <unknown>
  55:     0x7f5d05c27d8a - __libc_start_main
  56:     0x55d6a0de3019 - <unknown>
  57:                0x0 - <unknown>

error: the compiler unexpectedly panicked. this is a bug.

note: we would appreciate a bug report: https://github.com/rust-lang/rustfmt/issues/new?labels=bug

note: please attach the file at `/tmp/fmt/rustc-ice-2023-08-14T21:36:54.460559654Z-52165.txt` to your bug report

query stack during panic:
end of query stack
Diff in /tmp/fmt/93B5BD0690DC27A06716E0D5FDCE8EF7E31E4A69EA999D9797761DC9851406DC.rs at line 1:
 fn main() {
     println!("{}", builtin # offset_of(A, 0. 1.1.1));
-
 }
```

`rustfmt 1.6.0-nightly (1b198b3 2023-08-13)`

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"eval-exec"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->
