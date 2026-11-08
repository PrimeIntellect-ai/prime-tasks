ICE `error was constructed but not emitted`
````rust
cfg_if::cfg_if! {
    if #[cfg(windows)] {
    } else if #(&cpus) {
    } else [libc::CTL_HW, libc::HW_NCPU, 0, 0]
}
````

````
error: internal compiler error: the following error was constructed but not emitted

error: expected one of `!` or `[`, found `(`
 --> /tmp/im/D148C7688C5A01A6B9DD473ACF70135F85C41E99C693835C947E942C30ECD884.rs:3:16
  |
3 |     } else if #(&cpus) {
  |                ^ expected one of `!` or `[`

thread 'main' panicked at 'error was constructed but not emitted', compiler/rustc_errors/src/diagnostic_builder.rs:780:21
stack backtrace:
   0:     0x7f4fb0f65e8a - std::backtrace_rs::backtrace::libunwind::trace::hc07ec51854030801
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/../../backtrace/src/backtrace/libunwind.rs:93:5
   1:     0x7f4fb0f65e8a - std::backtrace_rs::backtrace::trace_unsynchronized::hd5249f53d09c2c41
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/../../backtrace/src/backtrace/mod.rs:66:5
   2:     0x7f4fb0f65e8a - std::sys_common::backtrace::_print_fmt::h7a58bb30aee44196
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:65:5
   3:     0x7f4fb0f65e8a - <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt::h4f2b7c295e3f8019
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:44:22
   4:     0x7f4fb0fc9e6f - core::fmt::write::h10777037b979b8b8
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/fmt/mod.rs:1254:17
   5:     0x7f4fb0f58ac5 - std::io::Write::write_fmt::he1dc4aa4bd2563db
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/io/mod.rs:1698:15
   6:     0x7f4fb0f65c55 - std::sys_common::backtrace::_print::h163c7799d3150ce8
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:47:5
   7:     0x7f4fb0f65c55 - std::sys_common::backtrace::print::h3cf13564ddfd5c0e
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:34:9
   8:     0x7f4fb0f688fe - std::panicking::default_hook::{{closure}}::h999811fec35f64bf
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:269:22
   9:     0x7f4fb0f686a5 - std::panicking::default_hook::he182d48ca482e8b2
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:288:9
  10:     0x7f4fb0f68f6e - std::panicking::rust_panic_with_hook::h2bc066147eaf9845
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:690:13
  11:     0x7f4fb0f68e22 - std::panicking::begin_panic_handler::{{closure}}::h1e4368c427832fe9
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:579:13
  12:     0x7f4fb0f662f6 - std::sys_common::backtrace::__rust_end_short_backtrace::h5466480ef33b438e
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:150:18
  13:     0x7f4fb0f68bc2 - rust_begin_unwind
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:577:5
  14:     0x7f4fb0fc6273 - core::panicking::panic_fmt::ha28b6d803d12671b
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/panicking.rs:67:14
  15:     0x7f4fb2377875 - <rustc_errors[10b8f3037483a69]::diagnostic_builder::DiagnosticBuilderInner as core[a19e7c0c634483f1]::ops::drop::Drop>::drop
  16:     0x55b4b8a04b32 - rustfmt_nightly[e3445ded4feb3b46]::parse::macros::cfg_if::parse_cfg_if_inner
  17:     0x55b4b8ab2219 - <rustfmt_nightly[e3445ded4feb3b46]::modules::visitor::CfgIfVisitor as rustc_ast[b583ee7534cdfdf7]::visit::Visitor>::visit_mac_call
  18:     0x55b4b8a442f1 - rustc_ast[b583ee7534cdfdf7]::visit::walk_item::<rustfmt_nightly[e3445ded4feb3b46]::modules::visitor::CfgIfVisitor>
  19:     0x55b4b8ada58d - <rustfmt_nightly[e3445ded4feb3b46]::modules::ModResolver>::visit_cfg_if
  20:     0x55b4b8ada9c6 - <rustfmt_nightly[e3445ded4feb3b46]::modules::ModResolver>::visit_mod_from_ast
  21:     0x55b4b8ada015 - <rustfmt_nightly[e3445ded4feb3b46]::modules::ModResolver>::visit_crate
  22:     0x55b4b8998533 - rustfmt_nightly[e3445ded4feb3b46]::formatting::format_project::<rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>
  23:     0x55b4b89959d0 - <scoped_tls[abd3470abb840dd8]::ScopedKey<rustc_span[e810f079a636b72c]::SessionGlobals>>::with::<<rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format_input_inner::{closure#0}, core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>>
  24:     0x55b4b8992a7f - <scoped_tls[abd3470abb840dd8]::ScopedKey<rustc_span[e810f079a636b72c]::SessionGlobals>>::set::<rustc_span[e810f079a636b72c]::create_session_if_not_set_then<core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>, <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format_input_inner::{closure#0}>::{closure#0}, core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>>
  25:     0x55b4b89bb650 - <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format
  26:     0x55b4b89aab05 - rustfmt[fd29d8685e71f599]::format_and_emit_report::<std[6ff7f37a454f70cc]::io::stdio::Stdout>
  27:     0x55b4b89b9b89 - <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::override_config::<rustfmt[fd29d8685e71f599]::format::{closure#0}, ()>
  28:     0x55b4b89a9865 - rustfmt[fd29d8685e71f599]::execute
  29:     0x55b4b89a7221 - rustfmt[fd29d8685e71f599]::main
  30:     0x55b4b89ba483 - std[6ff7f37a454f70cc]::sys_common::backtrace::__rust_begin_short_backtrace::<fn(), ()>
  31:     0x55b4b89b8cc9 - std[6ff7f37a454f70cc]::rt::lang_start::<()>::{closure#0}
  32:     0x7f4fb0f4969e - core::ops::function::impls::<impl core::ops::function::FnOnce<A> for &F>::call_once::hd8ec26e1d0256733
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/ops/function.rs:287:13
  33:     0x7f4fb0f4969e - std::panicking::try::do_call::ha93a022fbffe13f1
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:485:40
  34:     0x7f4fb0f4969e - std::panicking::try::hb1493baa50505ff7
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:449:19
  35:     0x7f4fb0f4969e - std::panic::catch_unwind::h68d19a9efbc50ca2
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panic.rs:140:14
  36:     0x7f4fb0f4969e - std::rt::lang_start_internal::{{closure}}::hfefbc424423bf0ab
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/rt.rs:148:48
  37:     0x7f4fb0f4969e - std::panicking::try::do_call::h33a3e76f78055d3b
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:485:40
  38:     0x7f4fb0f4969e - std::panicking::try::hf16a19af84a23805
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:449:19
  39:     0x7f4fb0f4969e - std::panic::catch_unwind::hfd39d2618b0c9350
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panic.rs:140:14
  40:     0x7f4fb0f4969e - std::rt::lang_start_internal::h8eb39434a671d889
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/rt.rs:148:20
  41:     0x55b4b89ab8a5 - main
  42:     0x7f4fb0bc3790 - <unknown>
  43:     0x7f4fb0bc384a - __libc_start_main
  44:     0x55b4b898ec59 - <unknown>
  45:                0x0 - <unknown>
````
