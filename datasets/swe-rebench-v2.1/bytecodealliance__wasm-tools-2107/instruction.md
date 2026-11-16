Panic parsing handcrafted WIT
`wasm-tools print` crashes given following WAT:

```wat
(component
  (core module $m
    (func (export "wasi:cli/run@0.2.0#run") (result i32)
      i32.const 0
    )
  )
  (core instance $mi (instantiate $m))
  (type $result_ty (result))
  (type $run_ty (func (result $result_ty)))
  (func $run (type $run_ty) (canon lift (core func $mi "wasi:cli/run@0.2.0#run")))
  (component $run_comp
    (export $export_run "run" (func $run) (func (type $run_ty)))
  )
  (instance $run_inst (instantiate $run_comp))
  (export $run_iface "wasi:cli/run@0.2.0" (instance $run_inst))
)
```

backtrace:
```
thread 'main' panicked at /Users/rvolosatovs/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wast-227.0.1/src/component/resolve.rs:1120:18:
internal error: entered unreachable code: not an outer alias namespace
stack backtrace:
   0:        0x105356240 - <std::sys::backtrace::BacktraceLock::print::DisplayBacktrace as core::fmt::Display>::fmt::h39ba3129e355bb22
   1:        0x1053746bc - core::fmt::write::h8b50d3a0f616451a
   2:        0x105352f24 - std::io::Write::write_fmt::h4b3bbae7048e35f8
   3:        0x1053560f4 - std::sys::backtrace::BacktraceLock::print::h7934b1e389160086
   4:        0x105357040 - std::panicking::default_hook::{{closure}}::hbcd636b20f603d1e
   5:        0x105356e74 - std::panicking::default_hook::ha9081970ba26bc6c
   6:        0x105357830 - std::panicking::rust_panic_with_hook::h9a5dc30b684e2ff4
   7:        0x105357480 - std::panicking::begin_panic_handler::{{closure}}::hbcb5de8b840ae91c
   8:        0x105356704 - std::sys::backtrace::__rust_end_short_backtrace::ha657d4b4d65dc993
   9:        0x105357160 - _rust_begin_unwind
  10:        0x1053dcbd0 - core::panicking::panic_fmt::hda207213c7ca0065
  11:        0x1050d9ef4 - wast::component::resolve::Resolver::resolve_ns::h3907170d9a806abf
  12:        0x1050d94b8 - wast::component::resolve::Resolver::component_item_ref::h60fef946f2c3a8c9
  13:        0x1050d6bcc - wast::component::resolve::Resolver::fields::h881b1ad23d9e9c76
  14:        0x1050d6918 - wast::component::resolve::Resolver::fields::h881b1ad23d9e9c76
  15:        0x10509020c - wast::core::binary::EncodeOptions::encode_wat::h79165fb93a6d183d
  16:        0x104ff8390 - wat::Parser::_parse_str::h9fabe1d2f28e89bd
  17:        0x104ff809c - wat::Parser::parse_bytes::hfde312c15929e3f8
  18:        0x104ff7da8 - wat::Parser::_parse_file::h8752b3e3e911accc
  19:        0x104ded27c - wasm_tools::InputArg::parse_wasm::h5ce5789403251741
  20:        0x104b41d40 - wasm_tools::WasmTools::run::hc81b9c6b9d0a8f55
  21:        0x104b3d158 - wasm_tools::main::hcf85427c2425b2ca
  22:        0x104bab048 - std::sys::backtrace::__rust_begin_short_backtrace::h2ccac9dc7d59e1d2
  23:        0x104b96dcc - std::rt::lang_start::{{closure}}::heea241c4c4740fa6
  24:        0x10534c260 - std::rt::lang_start_internal::hf1bc3d9041088441
  25:        0x104b4abc8 - _main
```

```
wasm-tools 1.227.1
```

The cause of this panic is the `$run` in the `$run_comp` component, it can be avoided with:
```diff
@@ -14,8 +14,12 @@
   (type $run_ty (func (result $result_ty)))
   (func $run (type $run_ty) (canon lift (core func $mi "wasi:cli/run@0.2.0#run")))
   (component $run_comp
+    (import "import-func-run" (func $run (type $run_ty)))
     (export $export_run "run" (func $run) (func (type $run_ty)))
   )
-  (instance $run_inst (instantiate $run_comp))
+  (instance $run_inst (instantiate $run_comp
+      (with "import-func-run" (func $run))
+    )
+  )
   (export $run_iface "wasi:cli/run@0.2.0" (instance $run_inst))
 )
```

I'm still going through the [spec](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md#alias-definitions) to figure out whether such references are actually allowed, but I'm guessing they should not be

### Additional contract requirements

- When an outer alias targets the function item `x`, report exactly: `outer item \`x\` is not a module, type, or component`.
