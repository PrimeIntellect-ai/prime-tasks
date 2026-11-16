'Argument 'x' is required and can't have a default value' when using default_value_os with #[derive(Clap)]
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the existing issues

### Rust Version

rustc 1.56.1 (59eed8a2a 2021-11-01)

### Clap Version

3.0.0-beta.5

### Minimal reproducible code

```rust
#[derive(clap::Parser)]
pub struct Options2 {
    #[clap(default_value_os = ("123".as_ref()))]
    x: String,
}

fn main() {
    let args = Options2::parse();
}
```


### Steps to reproduce the bug with the above code

`cargo run`

### Actual Behaviour

Panics with
```
thread 'main' panicked at 'Argument 'x' is required and can't have a default value', C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\arg\debug_asserts.rs:39:9
stack backtrace:
   0:     0x7ff798963f7e - std::backtrace_rs::backtrace::dbghelp::trace
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\..\..\backtrace\src\backtrace\dbghelp.rs:98
   1:     0x7ff798963f7e - std::backtrace_rs::backtrace::trace_unsynchronized
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\..\..\backtrace\src\backtrace\mod.rs:66
   2:     0x7ff798963f7e - std::sys_common::backtrace::_print_fmt
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\sys_common\backtrace.rs:67
   3:     0x7ff798963f7e - std::sys_common::backtrace::_print::impl$0::fmt
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\sys_common\backtrace.rs:46
   4:     0x7ff798975d9a - core::fmt::write
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\core\src\fmt\mod.rs:1150
   5:     0x7ff798961738 - std::io::Write::write_fmt<std::sys::windows::stdio::Stderr>
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\io\mod.rs:1667
   6:     0x7ff798966466 - std::sys_common::backtrace::_print
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\sys_common\backtrace.rs:49
   7:     0x7ff798966466 - std::sys_common::backtrace::print
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\sys_common\backtrace.rs:36
   8:     0x7ff798966466 - std::panicking::default_hook::closure$1
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:210
   9:     0x7ff798965f54 - std::panicking::default_hook
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:227
  10:     0x7ff798966ac5 - std::panicking::rust_panic_with_hook
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:624
  11:     0x7ff7989666ab - std::panicking::begin_panic_handler::closure$0
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:521
  12:     0x7ff7989648c7 - std::sys_common::backtrace::__rust_end_short_backtrace<std::panicking::begin_panic_handler::closure$0,never$>
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\sys_common\backtrace.rs:141
  13:     0x7ff798966609 - std::panicking::begin_panic_handler
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:517
  14:     0x7ff79897b57c - std::panicking::begin_panic_fmt
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:460
  15:     0x7ff79883b332 - clap::build::arg::debug_asserts::assert_arg
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\arg\debug_asserts.rs:39
  16:     0x7ff7988169bd - clap::build::app::debug_asserts::assert_app
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\debug_asserts.rs:90
  17:     0x7ff7987d7504 - clap::build::app::App::_build
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\mod.rs:2460
  18:     0x7ff7987d7060 - clap::build::app::App::_do_parse
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\mod.rs:2389
  19:     0x7ff7987d6a99 - clap::build::app::App::try_get_matches_from_mut<ref_mut$<std::env::ArgsOs>,std::ffi::os_str::OsString>
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\mod.rs:2278
  20:     0x7ff798791a25 - clap::build::app::App::get_matches_from<ref_mut$<std::env::ArgsOs>,std::ffi::os_str::OsString>
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\mod.rs:2112
  21:     0x7ff7987935a4 - clap::build::app::App::get_matches
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\app\mod.rs:2012
  22:     0x7ff7987918c1 - clap::derive::Parser::parse<edge::Options2>
                               at C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\derive.rs:76
  23:     0x7ff79879110e - edge::main
                               at D:\git\spectrum\edge-cli\src\main.rs:120
  24:     0x7ff798792f9b - core::ops::function::FnOnce::call_once<void (*)(),tuple$<> >
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\library\core\src\ops\function.rs:227
  25:     0x7ff79879236b - std::sys_common::backtrace::__rust_begin_short_backtrace<void (*)(),tuple$<> >
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\library\std\src\sys_common\backtrace.rs:125
  26:     0x7ff7987925c1 - std::rt::lang_start::closure$0<tuple$<> >
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\library\std\src\rt.rs:63
  27:     0x7ff798966f16 - core::ops::function::impls::impl$2::call_once
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\library\core\src\ops\function.rs:259
  28:     0x7ff798966f16 - std::panicking::try::do_call
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:403
  29:     0x7ff798966f16 - std::panicking::try
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:367
  30:     0x7ff798966f16 - std::panic::catch_unwind
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panic.rs:129
  31:     0x7ff798966f16 - std::rt::lang_start_internal::closure$2
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\rt.rs:45
  32:     0x7ff798966f16 - std::panicking::try::do_call
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:403
  33:     0x7ff798966f16 - std::panicking::try
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panicking.rs:367
  34:     0x7ff798966f16 - std::panic::catch_unwind
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\panic.rs:129
  35:     0x7ff798966f16 - std::rt::lang_start_internal
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\/library\std\src\rt.rs:45
  36:     0x7ff79879258f - std::rt::lang_start<tuple$<> >
                               at /rustc/59eed8a2aac0230a8b53e89d4e99d55912ba6b35\library\std\src\rt.rs:62
  37:     0x7ff798791476 - main
  38:     0x7ff79897a170 - invoke_main
                               at d:\a01\_work\2\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl:78
  39:     0x7ff79897a170 - __scrt_common_main_seh
                               at d:\a01\_work\2\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl:288
  40:     0x7ff9916137e4 - BaseThreadInitThunk
  41:     0x7ff993dbcb61 - RtlUserThreadStart
```

### Expected Behaviour

The behaviour should be the same as if I used `default_value = "123"`, i.e it exits successfully.

### Additional Context

_No response_

### Debug Output

```
[            clap::build::app]  App::_do_parse
[            clap::build::app]  App::_build
[            clap::build::app]  App::_propagate:edge-cli
[            clap::build::app]  App::_check_help_and_version
[            clap::build::app]  App::_check_help_and_version: Removing generated version
[            clap::build::app]  App::_propagate_global_args:edge-cli
[            clap::build::app]  App::_derive_display_order:edge-cli
[clap::build::app::debug_asserts]       App::_debug_asserts
[clap::build::arg::debug_asserts]       Arg::_debug_asserts:help
[clap::build::arg::debug_asserts]       Arg::_debug_asserts:x
thread 'main' panicked at 'Argument 'x' is required and can't have a default value', C:\Users\me\.cargo\registry\src\github.com-1ecc6299db9ec823\clap-3.0.0-beta.5\src\build\arg\debug_asserts.rs:39:9
```
