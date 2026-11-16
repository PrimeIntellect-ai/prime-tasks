ICE panicked at 'begin <= end (12 <= 11) when slicing `fn main() {}`''
````rust
macro_rules! statement {
    () => {;};
}
````

```
thread 'main' panicked at 'begin <= end (12 <= 11) when slicing `fn main() {}
`', src/tools/rustfmt/src/lib.rs:393:47
stack backtrace:
   0:     0x7f4cbdd65e8a - std::backtrace_rs::backtrace::libunwind::trace::hc07ec51854030801
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/../../backtrace/src/backtrace/libunwind.rs:93:5
   1:     0x7f4cbdd65e8a - std::backtrace_rs::backtrace::trace_unsynchronized::hd5249f53d09c2c41
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/../../backtrace/src/backtrace/mod.rs:66:5
   2:     0x7f4cbdd65e8a - std::sys_common::backtrace::_print_fmt::h7a58bb30aee44196
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:65:5
   3:     0x7f4cbdd65e8a - <std::sys_common::backtrace::_print::DisplayBacktrace as core::fmt::Display>::fmt::h4f2b7c295e3f8019
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:44:22
   4:     0x7f4cbddc9e6f - core::fmt::write::h10777037b979b8b8
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/fmt/mod.rs:1254:17
   5:     0x7f4cbdd58ac5 - std::io::Write::write_fmt::he1dc4aa4bd2563db
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/io/mod.rs:1698:15
   6:     0x7f4cbdd65c55 - std::sys_common::backtrace::_print::h163c7799d3150ce8
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:47:5
   7:     0x7f4cbdd65c55 - std::sys_common::backtrace::print::h3cf13564ddfd5c0e
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:34:9
   8:     0x7f4cbdd688fe - std::panicking::default_hook::{{closure}}::h999811fec35f64bf
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:269:22
   9:     0x7f4cbdd686a5 - std::panicking::default_hook::he182d48ca482e8b2
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:288:9
  10:     0x7f4cbdd68f6e - std::panicking::rust_panic_with_hook::h2bc066147eaf9845
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:690:13
  11:     0x7f4cbdd68e69 - std::panicking::begin_panic_handler::{{closure}}::h1e4368c427832fe9
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:581:13
  12:     0x7f4cbdd662f6 - std::sys_common::backtrace::__rust_end_short_backtrace::h5466480ef33b438e
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/sys_common/backtrace.rs:150:18
  13:     0x7f4cbdd68bc2 - rust_begin_unwind
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:577:5
  14:     0x7f4cbddc6273 - core::panicking::panic_fmt::ha28b6d803d12671b
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/panicking.rs:67:14
  15:     0x7f4cbddcf28f - core::str::slice_error_fail_rt::h8157873ce0ac4c9d
  16:     0x7f4cbddcf0d7 - core::str::slice_error_fail::hc96d17d855cd472b
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/str/mod.rs:86:9
  17:     0x55ba79b8707a - rustfmt_nightly[e3445ded4feb3b46]::format_code_block
  18:     0x55ba79a92c28 - <rustfmt_nightly[e3445ded4feb3b46]::macros::MacroBranch>::rewrite
  19:     0x55ba79ab645d - <rustfmt_nightly[e3445ded4feb3b46]::lists::ListItems<core[a19e7c0c634483f1]::slice::iter::Iter<rustfmt_nightly[e3445ded4feb3b46]::macros::MacroBranch>, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#1}, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#2}, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#3}> as core[a19e7c0c634483f1]::iter::traits::iterator::Iterator>::next
  20:     0x55ba79b2db01 - <alloc[827ef145a957661e]::vec::Vec<rustfmt_nightly[e3445ded4feb3b46]::lists::ListItem> as alloc[827ef145a957661e]::vec::spec_from_iter::SpecFromIter<rustfmt_nightly[e3445ded4feb3b46]::lists::ListItem, rustfmt_nightly[e3445ded4feb3b46]::lists::ListItems<core[a19e7c0c634483f1]::slice::iter::Iter<rustfmt_nightly[e3445ded4feb3b46]::macros::MacroBranch>, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#1}, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#2}, rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def::{closure#3}>>>::from_iter
  21:     0x55ba79a8b843 - rustfmt_nightly[e3445ded4feb3b46]::macros::rewrite_macro_def
  22:     0x55ba79b4ff0a - <rustfmt_nightly[e3445ded4feb3b46]::visitor::FmtVisitor>::visit_item
  23:     0x55ba79b45049 - <rustfmt_nightly[e3445ded4feb3b46]::visitor::FmtVisitor>::visit_items_with_reordering
  24:     0x55ba79b5543f - <rustfmt_nightly[e3445ded4feb3b46]::visitor::FmtVisitor>::walk_mod_items
  25:     0x55ba79b56037 - <rustfmt_nightly[e3445ded4feb3b46]::visitor::FmtVisitor>::format_separate_mod
  26:     0x55ba799da9c5 - rustfmt_nightly[e3445ded4feb3b46]::formatting::format_project::<rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>
  27:     0x55ba799d79d0 - <scoped_tls[abd3470abb840dd8]::ScopedKey<rustc_span[e810f079a636b72c]::SessionGlobals>>::with::<<rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format_input_inner::{closure#0}, core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>>
  28:     0x55ba799d4a7f - <scoped_tls[abd3470abb840dd8]::ScopedKey<rustc_span[e810f079a636b72c]::SessionGlobals>>::set::<rustc_span[e810f079a636b72c]::create_session_if_not_set_then<core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>, <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format_input_inner::{closure#0}>::{closure#0}, core[a19e7c0c634483f1]::result::Result<rustfmt_nightly[e3445ded4feb3b46]::FormatReport, rustfmt_nightly[e3445ded4feb3b46]::ErrorKind>>
  29:     0x55ba799fd650 - <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::format
  30:     0x55ba799ecb05 - rustfmt[fd29d8685e71f599]::format_and_emit_report::<std[6ff7f37a454f70cc]::io::stdio::Stdout>
  31:     0x55ba799fbb89 - <rustfmt_nightly[e3445ded4feb3b46]::Session<std[6ff7f37a454f70cc]::io::stdio::Stdout>>::override_config::<rustfmt[fd29d8685e71f599]::format::{closure#0}, ()>
  32:     0x55ba799eb865 - rustfmt[fd29d8685e71f599]::execute
  33:     0x55ba799e9221 - rustfmt[fd29d8685e71f599]::main
  34:     0x55ba799fc483 - std[6ff7f37a454f70cc]::sys_common::backtrace::__rust_begin_short_backtrace::<fn(), ()>
  35:     0x55ba799facc9 - std[6ff7f37a454f70cc]::rt::lang_start::<()>::{closure#0}
  36:     0x7f4cbdd4969e - core::ops::function::impls::<impl core::ops::function::FnOnce<A> for &F>::call_once::hd8ec26e1d0256733
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/core/src/ops/function.rs:287:13
  37:     0x7f4cbdd4969e - std::panicking::try::do_call::ha93a022fbffe13f1
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:485:40
  38:     0x7f4cbdd4969e - std::panicking::try::hb1493baa50505ff7
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:449:19
  39:     0x7f4cbdd4969e - std::panic::catch_unwind::h68d19a9efbc50ca2
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panic.rs:140:14
  40:     0x7f4cbdd4969e - std::rt::lang_start_internal::{{closure}}::hfefbc424423bf0ab
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/rt.rs:148:48
  41:     0x7f4cbdd4969e - std::panicking::try::do_call::h33a3e76f78055d3b
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:485:40
  42:     0x7f4cbdd4969e - std::panicking::try::hf16a19af84a23805
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panicking.rs:449:19
  43:     0x7f4cbdd4969e - std::panic::catch_unwind::hfd39d2618b0c9350
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/panic.rs:140:14
  44:     0x7f4cbdd4969e - std::rt::lang_start_internal::h8eb39434a671d889
                               at /rustc/17c11672167827b0dd92c88ef69f24346d1286dd/library/std/src/rt.rs:148:20
  45:     0x55ba799ed8a5 - main
  46:     0x7f4cbd9c3790 - <unknown>
  47:     0x7f4cbd9c384a - __libc_start_main
  48:     0x55ba799d0c59 - <unknown>
  49:                0x0 - <unknown>
```

### Additional contract requirements

- When formatting this input, produce exactly:
```rust
macro_rules! statement {
    () => {};
}
```
