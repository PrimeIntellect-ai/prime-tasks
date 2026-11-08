instantiate fuzzbug: Using a sunk load's result in a register
https://oss-fuzz.com/testcase-detail/5155715978756096

<details>
<summary>Stack trace</summary>

```
ERROR: AddressSanitizer: ABRT on unknown address 0x053900001862 (pc 0x7fdfc8c5818b bp 0x7fdfc46c4f70 sp 0x7fdfc46c4ce0 T2)
--
  | SCARINESS: 10 (signal)
  | #0 0x7fdfc8c5818b in raise /build/glibc-eX1tMB/glibc-2.31/sysdeps/unix/sysv/linux/raise.c:51:1
  | #1 0x7fdfc8c37858 in abort /build/glibc-eX1tMB/glibc-2.31/stdlib/abort.c:79:7
  | #2 0x555929a04786 in std::sys::unix::abort_internal::h9da1027ff38fb88e /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/sys/unix/mod.rs:293:14
  | #3 0x55592620b7a6 in std::process::abort::h035a89b8d6e3a675 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/process.rs:2119:5
  | #4 0x555929985323 in libfuzzer_sys::initialize::_$u7b$u7b$closure$u7d$u7d$::h8b17fedced5cb592 /rust/registry/src/github.com-1ecc6299db9ec823/libfuzzer-sys-0.4.3/src/lib.rs:57:9
  | #5 0x555929a00a2c in std::panicking::rust_panic_with_hook::hfaad0ec4972467c1 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:702:17
  | #6 0x555929a00840 in std::panicking::begin_panic_handler::_$u7b$u7b$closure$u7d$u7d$::h401c5684148433ac /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:586:13
  | #7 0x5559299fed0b in std::sys_common::backtrace::__rust_end_short_backtrace::h356ecf2a7ec67271 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/sys_common/backtrace.rs:138:18
  | #8 0x555929a005a1 in rust_begin_unwind /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:584:5
  | #9 0x55592620cbd2 in core::panicking::panic_fmt::h9555dfef52eae25e /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panicking.rs:142:14
  | #10 0x55592620ca9c in core::panicking::panic::hbe0e36c7510ee8e3 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panicking.rs:48:5
  | #11 0x55592807f561 in cranelift_codegen::machinst::lower::Lower$LT$I$GT$::put_value_in_regs::h6b3579e35e883d9c wasmtime/cranelift/codegen/src/machinst/lower.rs:1240:13
  | #12 0x5559283edd19 in cranelift_codegen::isa::x64::lower::isle::_$LT$impl$u20$cranelift_codegen..isa..x64..lower..isle..generated_code..Context$u20$for$u20$cranelift_codegen..machinst..isle..IsleContext$LT$cranelift_codegen..isa..x64..lower..isle..generated_code..MInst$C$cranelift_codegen..settings..Flags$C$cranelift_codegen..isa..x64..settings..Flags$C$6_usize$GT$GT$::put_in_reg::hd61ac63687583354 wasmtime/cranelift/codegen/src/machinst/isle.rs:159:13
  | #13 0x5559283edd19 in cranelift_codegen::isa::x64::lower::isle::generated_code::constructor_put_in_xmm::h6c4f4018b33e9652 wasmtime/target/x86_64-unknown-linux-gnu/release/build/cranelift-codegen-2a8c5675489ecc10/out/isle_x64.rs:1692:19
  | #14 0x55592845bcb3 in cranelift_codegen::isa::x64::lower::isle::generated_code::constructor_lower::ha986ad5563068bae wasmtime/target/x86_64-unknown-linux-gnu/release/build/cranelift-codegen-2a8c5675489ecc10/out/isle_x64.rs:12145:35
  | #15 0x5559282623f4 in cranelift_codegen::isa::x64::lower::isle::lower::_$u7b$u7b$closure$u7d$u7d$::h8afc68d76ea1a20f wasmtime/cranelift/codegen/src/isa/x64/lower/isle.rs:70:20
  | #16 0x5559282623f4 in cranelift_codegen::machinst::isle::lower_common::h165dc6c0a12ed7de wasmtime/cranelift/codegen/src/machinst/isle.rs:1182:21
  | #17 0x5559282623f4 in cranelift_codegen::isa::x64::lower::isle::lower::h9fff8cc9b5841a88 wasmtime/cranelift/codegen/src/isa/x64/lower/isle.rs:63:5
  | #18 0x5559282623f4 in cranelift_codegen::isa::x64::lower::lower_insn_to_regs::h9f1f8496d381da1d wasmtime/cranelift/codegen/src/isa/x64/lower.rs:311:21
  | #19 0x5559282623f4 in cranelift_codegen::isa::x64::lower::_$LT$impl$u20$cranelift_codegen..machinst..lower..LowerBackend$u20$for$u20$cranelift_codegen..isa..x64..X64Backend$GT$::lower::h3d309519bc912dc1 wasmtime/cranelift/codegen/src/isa/x64/lower.rs:591:9
  | #20 0x55592805f516 in cranelift_codegen::machinst::lower::Lower$LT$I$GT$::lower_clif_block::ha56e3685599e43bd wasmtime/cranelift/codegen/src/machinst/lower.rs:709:17
  | #21 0x55592805f516 in cranelift_codegen::machinst::lower::Lower$LT$I$GT$::lower::h7350ae86d0fd50e1 wasmtime/cranelift/codegen/src/machinst/lower.rs:980:17
  | #22 0x5559280c650e in cranelift_codegen::machinst::compile::compile::h57386f910d23b37f wasmtime/cranelift/codegen/src/machinst/compile.rs:28:9
  | #23 0x55592827941e in cranelift_codegen::isa::x64::X64Backend::compile_vcode::h2d852a1048691c8e wasmtime/cranelift/codegen/src/isa/x64/mod.rs:57:9
  | #24 0x55592827941e in _$LT$cranelift_codegen..isa..x64..X64Backend$u20$as$u20$cranelift_codegen..isa..TargetIsa$GT$::compile_function::hf10cfe06fd2b0ac8 wasmtime/cranelift/codegen/src/isa/x64/mod.rs:68:40
  | #25 0x55592831d8d9 in cranelift_codegen::context::Context::compile_stencil::he0326b1016760743 wasmtime/cranelift/codegen/src/context.rs:173:9
  | #26 0x55592831ed0e in cranelift_codegen::context::Context::compile::h25272eb21d18139b wasmtime/cranelift/codegen/src/context.rs:185:23
  | #27 0x55592831b3f0 in cranelift_codegen::context::Context::compile_and_emit::he8d34c68051dff05 wasmtime/cranelift/codegen/src/context.rs:121:29
  | #28 0x555927cdec2d in wasmtime_cranelift::compiler::compile_maybe_cached::h73d02fb71840f254 wasmtime/crates/cranelift/src/compiler.rs:528:25
  | #29 0x555927cc73e3 in _$LT$wasmtime_cranelift..compiler..Compiler$u20$as$u20$wasmtime_environ..compilation..Compiler$GT$::compile_function::h43763e9daedb34dc wasmtime/crates/cranelift/src/compiler.rs:274:29
  | #30 0x5559276287bc in wasmtime::module::Module::compile_functions::_$u7b$u7b$closure$u7d$u7d$::_$u7b$u7b$closure$u7d$u7d$::hf4d1e9c131af2168 wasmtime/crates/wasmtime/src/module.rs:384:25
  | #31 0x55592748b1a8 in wasmtime::engine::Engine::run_maybe_parallel::_$u7b$u7b$closure$u7d$u7d$::h3ff6117233b5b7a2 wasmtime/crates/wasmtime/src/engine.rs:238:26
  | #32 0x55592748b1a8 in core::ops::function::impls::_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$u20$for$u20$RF$F$GT$::call_mut::h234195383ee97834 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/ops/function.rs:268:13
  | #33 0x55592748b1a8 in core::ops::function::impls::_$LT$impl$u20$core..ops..function..FnOnce$LT$A$GT$u20$for$u20$RF$mut$u20$F$GT$::call_once::heb9f5fd12b280de7 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/ops/function.rs:301:13
  | #34 0x55592748b1a8 in core::option::Option$LT$T$GT$::map::h2132c640bcd50657 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/option.rs:929:29
  | #35 0x55592748b1a8 in _$LT$core..iter..adapters..map..Map$LT$I$C$F$GT$u20$as$u20$core..iter..traits..iterator..Iterator$GT$::next::hab1d047f2ab420c1 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/iter/adapters/map.rs:103:9
  | #36 0x55592748b1a8 in _$LT$core..iter..adapters..map..Map$LT$I$C$F$GT$u20$as$u20$core..iter..traits..iterator..Iterator$GT$::next::hebfe90fd2cd9bc40 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/iter/adapters/map.rs:103:9
  | #37 0x55592748b1a8 in _$LT$core..iter..adapters..take_while..TakeWhile$LT$I$C$P$GT$u20$as$u20$core..iter..traits..iterator..Iterator$GT$::next::hdb9cb7501cc2cb63 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/iter/adapters/take_while.rs:46:21
  | #38 0x55592748b1a8 in _$LT$core..iter..adapters..map..Map$LT$I$C$F$GT$u20$as$u20$core..iter..traits..iterator..Iterator$GT$::next::h281d9ce5d7cb49d0 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/iter/adapters/map.rs:103:9
  | #39 0x55592754d217 in alloc::vec::Vec$LT$T$C$A$GT$::extend_desugared::hedcec18f2e14ebf1 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/alloc/src/vec/mod.rs:2749:35
  | #40 0x55592754d217 in _$LT$alloc..vec..Vec$LT$T$C$A$GT$u20$as$u20$alloc..vec..spec_extend..SpecExtend$LT$T$C$I$GT$GT$::spec_extend::ha2d095c164b5df95 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/alloc/src/vec/spec_extend.rs:18:9
  | #41 0x55592754d217 in _$LT$alloc..vec..Vec$LT$T$C$A$GT$u20$as$u20$core..iter..traits..collect..Extend$LT$T$GT$GT$::extend::h36d1ff927652ddc7 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/extend.rs:73:9
  | #42 0x55592754d217 in _$LT$rayon..iter..extend..ListVecFolder$LT$T$GT$u20$as$u20$rayon..iter..plumbing..Folder$LT$T$GT$GT$::consume_iter::h6dbbe8db5e965319 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/extend.rs:73:9
  | #43 0x55592754d217 in _$LT$rayon..iter..while_some..WhileSomeFolder$LT$C$GT$u20$as$u20$rayon..iter..plumbing..Folder$LT$core..option..Option$LT$T$GT$GT$GT$::consume_iter::h2524fc59f03f77c9 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/while_some.rs:139:21
  | #44 0x55592754d217 in _$LT$rayon..iter..map..MapFolder$LT$C$C$F$GT$u20$as$u20$rayon..iter..plumbing..Folder$LT$T$GT$GT$::consume_iter::ha3793527b33bc07b /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/map.rs:248:21
  | #45 0x55592754d217 in _$LT$rayon..iter..map..MapFolder$LT$C$C$F$GT$u20$as$u20$rayon..iter..plumbing..Folder$LT$T$GT$GT$::consume_iter::h016118e608ba7a8e /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/map.rs:248:21
  | #46 0x55592754d217 in rayon::iter::plumbing::Producer::fold_with::h6cdacd88d3a16912 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:110:9
  | #47 0x55592754d217 in rayon::iter::plumbing::bridge_producer_consumer::helper::h36bc427b579d07e8 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:438:13
  | #48 0x5559274ab547 in rayon::iter::plumbing::bridge_producer_consumer::helper::_$u7b$u7b$closure$u7d$u7d$::h4124d4e52d7357d7 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:418:21
  | #49 0x5559274ab547 in rayon_core::join::join_context::call_a::_$u7b$u7b$closure$u7d$u7d$::h42c1db1b970cd54c /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:124:17
  | #50 0x5559274ab547 in _$LT$core..panic..unwind_safe..AssertUnwindSafe$LT$F$GT$u20$as$u20$core..ops..function..FnOnce$LT$LP$RP$GT$GT$::call_once::h2c7fcb339523f7aa /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panic/unwind_safe.rs:271:9
  | #51 0x5559274ab547 in std::panicking::try::do_call::hacade4b9c59a4adf /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:492:40
  | #52 0x555927672936 in __rust_try wasmtime.1a80ab68-cgu.0:0
  | #53 0x55592749271f in std::panicking::try::h05f9a3627d6c9271 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:456:19
  | #54 0x55592749271f in std::panic::catch_unwind::h8ba3574d32c6ccf1 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panic.rs:137:14
  | #55 0x55592749271f in rayon_core::unwind::halt_unwinding::hd41f3cdf07b6ddca /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/unwind.rs:17:5
  | #56 0x55592749271f in rayon_core::join::join_context::_$u7b$u7b$closure$u7d$u7d$::ha7cbb5f65af67737 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:141:24
  | #57 0x55592754db78 in rayon_core::registry::in_worker::h87b4c6be6e6b2bee /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:877:13
  | #58 0x55592754db78 in rayon_core::join::join_context::h3435ad365001f8ed /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:132:5
  | #59 0x55592754db78 in rayon::iter::plumbing::bridge_producer_consumer::helper::h36bc427b579d07e8 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:416:47
  | #60 0x55592762639a in rayon::iter::plumbing::bridge_producer_consumer::h9c73f8388884777a /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:397:12
  | #61 0x55592762639a in _$LT$rayon..iter..plumbing..bridge..Callback$LT$C$GT$u20$as$u20$rayon..iter..plumbing..ProducerCallback$LT$I$GT$GT$::callback::h799b5dafd3f07765 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:373:13
  | #62 0x55592762639a in _$LT$rayon..vec..Drain$LT$T$GT$u20$as$u20$rayon..iter..IndexedParallelIterator$GT$::with_producer::h101971a6dcb0251e /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/vec.rs:147:13
  | #63 0x55592762639a in _$LT$rayon..vec..IntoIter$LT$T$GT$u20$as$u20$rayon..iter..IndexedParallelIterator$GT$::with_producer::hbf36918a127b7fa5 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/vec.rs:83:9
  | #64 0x55592762639a in rayon::iter::plumbing::bridge::hbd7149178da5f82c /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/plumbing/mod.rs:357:12
  | #65 0x55592762639a in _$LT$rayon..vec..IntoIter$LT$T$GT$u20$as$u20$rayon..iter..ParallelIterator$GT$::drive_unindexed::h4442df225a6c01c4 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/vec.rs:58:9
  | #66 0x55592762639a in _$LT$rayon..iter..map..Map$LT$I$C$F$GT$u20$as$u20$rayon..iter..ParallelIterator$GT$::drive_unindexed::hb7ee4a062d63b22c /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/map.rs:49:9
  | #67 0x55592762639a in _$LT$rayon..iter..map..Map$LT$I$C$F$GT$u20$as$u20$rayon..iter..ParallelIterator$GT$::drive_unindexed::h0d8e504a4d3b59d0 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/map.rs:49:9
  | #68 0x55592762639a in _$LT$rayon..iter..while_some..WhileSome$LT$I$GT$u20$as$u20$rayon..iter..ParallelIterator$GT$::drive_unindexed::ha4fce93c01d93b03 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/while_some.rs:44:9
  | #69 0x55592762639a in rayon::iter::extend::_$LT$impl$u20$rayon..iter..ParallelExtend$LT$T$GT$u20$for$u20$alloc..vec..Vec$LT$T$GT$GT$::par_extend::h12e2783fba02e682 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/extend.rs:576:28
  | #70 0x55592762639a in rayon::iter::from_par_iter::collect_extended::h28c6954878fe80d0 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/from_par_iter.rs:17:5
  | #71 0x55592762639a in rayon::iter::from_par_iter::_$LT$impl$u20$rayon..iter..FromParallelIterator$LT$T$GT$u20$for$u20$alloc..vec..Vec$LT$T$GT$GT$::from_par_iter::h3bfd8a167474cb2e /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/from_par_iter.rs:30:9
  | #72 0x55592762639a in rayon::iter::ParallelIterator::collect::he51ec30503e40231 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/mod.rs:2046:9
  | #73 0x55592762639a in rayon::result::_$LT$impl$u20$rayon..iter..FromParallelIterator$LT$core..result..Result$LT$T$C$E$GT$GT$u20$for$u20$core..result..Result$LT$C$C$E$GT$GT$::from_par_iter::hcdc24905f47daba9 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/result.rs:121:26
  | #74 0x55592762639a in rayon::iter::ParallelIterator::collect::hc39d937e87d92c38 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-1.5.2/src/iter/mod.rs:2046:9
  | #75 0x55592762639a in wasmtime::engine::Engine::run_maybe_parallel::heaf514b5f15e395e wasmtime/crates/wasmtime/src/engine.rs:236:20
  | #76 0x55592762639a in wasmtime::module::Module::compile_functions::_$u7b$u7b$closure$u7d$u7d$::h2db9f536d88fcf0f wasmtime/crates/wasmtime/src/module.rs:381:29
  | #77 0x5559274ab1a6 in rayon_core::join::join::call::_$u7b$u7b$closure$u7d$u7d$::he352dd112d6823fe /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:102:18
  | #78 0x5559274ab1a6 in rayon_core::join::join_context::call_a::_$u7b$u7b$closure$u7d$u7d$::h0433892693a648b9 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:124:17
  | #79 0x5559274ab1a6 in _$LT$core..panic..unwind_safe..AssertUnwindSafe$LT$F$GT$u20$as$u20$core..ops..function..FnOnce$LT$LP$RP$GT$GT$::call_once::hd2b2ae30cde31141 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panic/unwind_safe.rs:271:9
  | #80 0x5559274ab1a6 in std::panicking::try::do_call::h9380e3e8c45ff187 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:492:40
  | #81 0x555927672936 in __rust_try wasmtime.1a80ab68-cgu.0:0
  | #82 0x555927491a1a in std::panicking::try::hbc8fdf3a7de854a8 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:456:19
  | #83 0x555927491a1a in std::panic::catch_unwind::h283e80e8a11228a3 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panic.rs:137:14
  | #84 0x555927491a1a in rayon_core::unwind::halt_unwinding::h6c8e3ab3d1722e65 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/unwind.rs:17:5
  | #85 0x555927491a1a in rayon_core::join::join_context::_$u7b$u7b$closure$u7d$u7d$::h902dcd7e2955810e /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/join/mod.rs:141:24
  | #86 0x5559274aaebc in rayon_core::registry::Registry::in_worker_cold::_$u7b$u7b$closure$u7d$u7d$::_$u7b$u7b$closure$u7d$u7d$::h1a047486ecd9a2ad /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:467:21
  | #87 0x5559274aaebc in _$LT$rayon_core..job..StackJob$LT$L$C$F$C$R$GT$u20$as$u20$rayon_core..job..Job$GT$::execute::call::_$u7b$u7b$closure$u7d$u7d$::h2902a5719a33fcac /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/job.rs:113:21
  | #88 0x5559274aaebc in _$LT$core..panic..unwind_safe..AssertUnwindSafe$LT$F$GT$u20$as$u20$core..ops..function..FnOnce$LT$LP$RP$GT$GT$::call_once::hbbd07f2b8619548e /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panic/unwind_safe.rs:271:9
  | #89 0x5559274aaebc in std::panicking::try::do_call::h7ebe5e3bfd2025a3 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:492:40
  | #90 0x555927672936 in __rust_try wasmtime.1a80ab68-cgu.0:0
  | #91 0x55592756c39c in std::panicking::try::hd41a20bc1216aa7b /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:456:19
  | #92 0x55592756c39c in std::panic::catch_unwind::h4d7ff3064a0bdc97 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panic.rs:137:14
  | #93 0x55592756c39c in rayon_core::unwind::halt_unwinding::h83da29866da18d32 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/unwind.rs:17:5
  | #94 0x55592756c39c in _$LT$rayon_core..job..StackJob$LT$L$C$F$C$R$GT$u20$as$u20$rayon_core..job..Job$GT$::execute::ha3b748b228f217a5 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/job.rs:119:38
  | #95 0x55592618d76a in rayon_core::job::JobRef::execute::h34d1d746fcf8c561 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:728:17
  | #96 0x55592618d76a in rayon_core::registry::WorkerThread::execute::h1ba186aa9ee7d065 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:751:9
  | #97 0x55592618d76a in rayon_core::registry::WorkerThread::wait_until_cold::h6e49926a820dcbb3 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:728:17
  | #98 0x55592856d3ef in rayon_core::registry::WorkerThread::wait_until::h755b15c871e9eca3 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:702:13
  | #99 0x55592856d3ef in rayon_core::registry::main_loop::h91c984286be7273b /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:835:5
  | #100 0x55592856d3ef in rayon_core::registry::ThreadBuilder::run::h7b0b4b104ed5fb0e /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:55:18
  | #101 0x55592853a926 in _$LT$rayon_core..registry..DefaultSpawn$u20$as$u20$rayon_core..registry..ThreadSpawn$GT$::spawn::_$u7b$u7b$closure$u7d$u7d$::ha0dd7d3b60463d22 /rust/registry/src/github.com-1ecc6299db9ec823/rayon-core-1.9.2/src/registry.rs:100:20
  | #102 0x55592853a926 in std::sys_common::backtrace::__rust_begin_short_backtrace::hf94b9ede0157f975 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/sys_common/backtrace.rs:122:18
  | #103 0x5559285406fa in std::thread::Builder::spawn_unchecked_::_$u7b$u7b$closure$u7d$u7d$::_$u7b$u7b$closure$u7d$u7d$::hc0b7bd2fe7847b17 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/thread/mod.rs:504:17
  | #104 0x5559285406fa in _$LT$core..panic..unwind_safe..AssertUnwindSafe$LT$F$GT$u20$as$u20$core..ops..function..FnOnce$LT$LP$RP$GT$GT$::call_once::h7f287efe71426200 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/panic/unwind_safe.rs:271:9
  | #105 0x5559285406fa in std::panicking::try::do_call::h4ab1625df7493dbc /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:492:40
  | #106 0x55592857c5b6 in __rust_try rayon_core.f334a033-cgu.0:0
  | #107 0x55592854662b in std::panicking::try::hb31068643f88152e /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panicking.rs:456:19
  | #108 0x55592854662b in std::panic::catch_unwind::hcbd92115b20e0cab /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/panic.rs:137:14
  | #109 0x55592854662b in std::thread::Builder::spawn_unchecked_::_$u7b$u7b$closure$u7d$u7d$::h18438683fd461279 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/thread/mod.rs:503:30
  | #110 0x55592854662b in core::ops::function::FnOnce::call_once$u7b$u7b$vtable.shim$u7d$u7d$::h885623308b888302 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/core/src/ops/function.rs:248:5
  | #111 0x555929a04162 in _$LT$alloc..boxed..Box$LT$F$C$A$GT$u20$as$u20$core..ops..function..FnOnce$LT$Args$GT$GT$::call_once::hd8b4f77c73b6de54 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/alloc/src/boxed.rs:1940:9
  | #112 0x555929a04162 in _$LT$alloc..boxed..Box$LT$F$C$A$GT$u20$as$u20$core..ops..function..FnOnce$LT$Args$GT$GT$::call_once::h396dcf115ad932d5 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/alloc/src/boxed.rs:1940:9
  | #113 0x555929a04162 in std::sys::unix::thread::Thread::new::thread_start::h004395cd09d806b0 /rustc/060e47f74a91b28c3db28d80a6a9d6841ca51026/library/std/src/sys/unix/thread.rs:108:17
  | #114 0x7fdfc8f62608 in start_thread /build/glibc-eX1tMB/glibc-2.31/nptl/pthread_create.c:477:8
  | #115 0x7fdfc8d34292 in __clone /build/glibc-eX1tMB/glibc-2.31/sysdeps/unix/sysv/linux/x86_64/clone.S:95
```
</details>


<details>
<summary>Input</summary>

```
Cfv///8JCQkoZnVuYzAmsnWOZs8RptkAqgBizmwuUjFNAAEBJEYAANpSMDYmsnWOZs8RptkAqgBi
zmwuUjD/////J0H/////////////////////////////////////////////////////////////
/////////////////////////zMzJrLP5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eVzdHJpY3Tl5eXl
5eXl5eXl5eXl5eXl5eXl//////8S//8zMyayz+Xl5eXl5eXl5eXl5eXl5eXl5eXl5eXlc3RyaWN0
5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl////////////////////////
////////////////////5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl
5f////8xNiayz+UBAAAAAAAAAeXl5eXl5eXl5eXl/////////zMzJrLP5eXl5eXl5eXl5eXl5eXl
5eXl5eXl5eVzdHJpY3Tl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eUk5eXl////
////////////////////////////////////////5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl
5eXl5eXl5eXl5eXl5eXl5f//29QpLChlbGVtCSRuJydgXFwnJ///CSRuSSctJycnCQppNjQuc2hy
X3M7Owlkcm9wbicAEChmdW5jCb5uAQAAAUknJycnCTZ4OC5zaGw7OwkKaTE2fng4LnNo5eXl5eXl
5eXlc3Ry7e3t7e3t7e3taWN05eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl
//////////////////////////////////////////////////r//8sxJrLP5eXl5eXl5eXl5eVt
CSRuJydgXFwnJ///CSRuSSctJycnCQppNjQuc2hyX3M7Owlkcm9wbicAEChmdW5jCb5uAQAAAUkn
JycnCTZ4OC5zaGw7OwkKaTE2fng4LnNo5eXl5eXl5eXlc3Ry7e3t7e3t7e3taWN05eXl5eXl5eXl
5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl////////////////////////////////////
////////////Gvr/BAD5+fn5+fn5efn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fl7
CiJ0eXBlIjogIkZlYXR1cmVDb2xsZWN0aW9uIiwKIm5hbWUiOiAidGVzdF90eXBlX3Byb21vdGlv
biIsCiJmZWF0dXJlcyI6IFsKeyAidHlwZSI6ICJGZWF0dXJlIiwgInByb3BlcnRpZXMiOiB7ICJi
b29sX3RoZW5fYm9vbCI6IHRydWUsICJib29sX3RoZW5faW50IjogMSwgImJvb2xfdGhlbl9pbnQ2
NCI6IDEsICLKb29sX3RoZW5fcmVhbCI6IDEuMCwgImJvb2xfdGhlbl9zdHJpbmciOiAidHJ1ZSIs
ICJib29sX3RoZW5fYm9vbGxpc3QiOiD/+v//yzEmss/l5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl
5eXl5eXl5eXl5eXl5eXl5QAGADMxLnN1YmZ1bmMJJG5JJG5JJycnJwkKac/Jh8fRjJeTOzsJCs/l
5eXl5eXl5eXl5eXl5eXl5eXl5eXl5XN0cmljdOXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl
5eXl5eXl5eXl5f///////////+Xl5eXl5eXl5XP///////8xNiayz+Xl5eXl5eXl5eXl5eXl5eXl
7eXl5eXlc3RyaWN05VsgdHJ1ZSBdLCAiYm9vbF90aGVuX2ludGxpc3QiOiBbIDEgXSwgImJvb3Ry
aW5nX3RoZW5fcmVhbCI6ICJ4IiwgInN0cmluZ190aGVuX3N0cmluZyI6ICJ4IiwgInN0cmluZ190
aGVuX2Jvb2xsaXN0IjogIngiLCAic3RyaW5nX3RoZW5faW50bGlzdCI6ICJ4IiwgInN0cmluZ190
aGVuX2ludCI6IFsgIngiIF0sICJzdHJpbmdfdGhlbl9kYXRldGltZSI6ICJ4IiwgImRhdGV0aW1l
X3RoZW5fc3RyaW5nIjogIjE5NzAtMDEtMDFUMDA6MDA6MDAiLCAiZGF0ZXRpbWVfdGhlbl9kYXRl
dGltZSI6ICIxOTcwXC8wMVwvMDEgMDA6MDA6MDAiLCAiYm9vbGxpc3RfdGhlbl9ib29sIjogWyB0
cnVlIF0sICJib29sbGlzdF90aGVuX2ludCI6IFsgMSBdLCAiYm9vbGxpc3RfdGhlbl9pbnQ2NCI6
IFsgMSBdLCAiYm9vbGxpc3RfdGhlbl9yZWFsIjogWyAxLjAgXSwgImJuX3N0cmluZ2xpc3QiOiBb
ICIwLjAxNTYyNSIgXSwgInN0cmluZ2xpc3RfdGhlbl9ib29sIjogWyAieCIgXSwgInN0cmluZ2xp
c3RfdGhlbl9pbnQiOiBbICJ4IiBdLCAic3RyaW5nbGlzdF90aGVuX2ludDY0IjogWyAieCIgXSwg
InN0cmluZ2xpc3RfdGhlbl9yZWFsIjogWyAieEUiIF0sICJzdHJpbmdsaXN0X3RoZW5fc3RyaW5n
IjogWyAieCIgXSwgInN0cmluZ2xpc3RfdGhlbl9ib29sbGlzdCI6IFsgInhddCJzICAsInJpbmds
aXN0X3RoZW5faW50bGlzdCI6IFsgIngiIF0sICJzdHJpbmdsaXN0X3RoZW5faW50NjRsaXN0Ijog
WyAieCIgXSwgInN0cmluZ2xpc3RfdGhlbl9wcm9iZXN0YWNrX1sgIngiIF0sICJzdHJpbmdsaXN0
X3RoZW5fc3RyaW5nbGlzdCI6IFsgIngiIF0gfSwgImdlb21ldHLbIjogbnVsbCB9LAp7ICJ0eXBl
IjogIkZlYXR1cmUiLCAicHJvcGVydGllcyI6IHsgImJvb2xfdGhlbl9ib29sIjogdHJ1ZSwgImJv
b2xfdGhlbl9pbnQiOiAxLCAiYm9vbF90aGVuX2ludDY0IjogMTIzNDU2Nzg5MDEyMywgImJvb2xf
dGhlbl9yZWFsIjogMC4wMTU2MjUsICJib29sX3RoZW5fc3RyaW5nIjogIngiLCAiYm9vbF90aGVu
X2Jvb2xsaXN0IjogWyB0cnVlIF0sICJib29sX3RoZW5faXJycnJycnJycnJycnJycnJycnJycnJy
cnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnL5+fn5+XJycnJycnJycnJycnJycnJycnJy
cnJycnJycnJoZW5fc3RyaW5nbGlzdCI6IFsgIngiIF0sICJzdHJpbmdfdGhlbl9kYXRldGltZSI6
ICJ4IiwgImRhdGV0aW1lX3RoZW5fc3RyaW5nIjogIjE5NzAtMDEtMDFUMDA6MDA6MDAiLCAiZGF0
ZXRpbWVfdGhlbl9kYXRldGltZSI6ICIxOTcwXC8wMVwvMDEgMDA6MDA6MDAiLCAiYm9vbGxpc3Rf
dGhlbl9ib29sIjogWyB0cnVlIF0sICJib29sbGlzdF90aGVuX2ludCI6IFsgMSBdLCAiYm9vbGxp
c3RfdGhlbl9pbnQ2NCI6IFsgMSBdLCAiYm9vbGxpc3RfdGhlbl9yZWFsIjogWyAxLjAgXSwgImJu
X3N0cmluZ2xpc3QiOiBbICIwLjAxNTYyNSLlLnNocl9zOzsJAGPl5eXl5eXl5eWl5eXl5f////8z
Myayz+Xl5eXl5eXl5eXl5eXl5eXl5eXl5eXlc3RyaWN05eXl5eXl5eXl////Cv/6CQkJCShmdW5j
CST////9pv/////+5v8Ytf/+//8A/zH/Kf//OyM7dDt0O3Q7dDt0O3Q7/////////////x8fHx8f
Hx8fHx8fHx8fHx8f//2m//////7m/xi1//7//wD/MP8p//87Izt0O3Q7dDt0O3Q7dDv/////////
////Hx////9JWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlNQ/29JRFssKywrKV1VTklUXzBbKTQp
///////3///////////v//8wdHP//25JT5MoS3JvdkFha1svtV3/MSEsLP9dRVBBUj1Nu6u6sVuO
LDD///////9JU1D/b///////H/8fIF0sICJzdHJpbmdsaXN0X3RoZW5fYm9vbCI6IFsfHx8fHx8f
CicnCmkyKLUv/QAAzABtAGNoaW5lX2NvZGVfY2ZnXwBoYXNfc3NlM///TP82////////////////
////////////////////////////////Xf//////////NC5uZQkKdjMyeDQubG9hZF8p////////
/f////3m+/////4Y/7UARgDM4eHh4eHh4eHh4eHhWuHhMOHh4eHh8eHh4eHh4eHh4eHh4eHh4eHh
4Vrh4eHh4eHh4eHh4S5zdHJ0YWLh4eHhICJ4IiBdLCAic3RyaW5nbGlzdF90aGVuX2ludCI6IFsg
IngiIF0sICJzdHJpbmdsaXN0X3RoZW5faW50NjQiOiBbICJ4IiD5+fn5+fn5+fldLCAiLAAAZW5f
aW50NjQiOiBbICJ4IiBdLCAic3RyaW5nbGlzdF90aGVuX3JlYWwiOiBbICJ4IiBdLCAic3RyaW5n
bGlzdF90aGVuX3N0cmluZyI6IFsgIngiIF0sICJzdHJpbmdsaXN0X3RoZW5fYm9vbGxpc3QiOiBb
ICJ4IiBdLCAic3RyaW5nbGlzdF90aGVuX2ludGxpc3QiOiBbICJ4IiBdLCAic3RyaW5nbGlzdF90
aGVuX2ludDY0bGlzdCI6IFsgIngiIF0sICJzdHJpbmdsaXN0X3RoZW5fcmVhbGxpc3QiOiBbICJ4
IiBdLCAic3RyaW5nbGlzdF90aGVuX3N0cmluZ2xpc3QiOiBbICJ4IiBdIH0sICJnZW9tZXRy2yI6
IG51bGwgfSwKeyAidHlwZSI6ICJGZWF0dXJlIiwgInByb3BlcnRpZXMiOiB7ICJib29sX3RoZW5f
Ym9vbCI6IHRydWUsICJib29sX3RoZW5faW50IjogMSwgImJvb2xfdGhlbl9pbnQ2NCI6IDEyMzQ1
Njc4OTAxMjMsICJib29sX3RoZW5fcmVhbCI6IDAuMDE1NjI1LCAiYm9vbF90aGVuX3N0cmluZyI6
ICJ4IiwgImJvb2xfdGhlbl9ib29sbGlzdCI6IFsgdHJ1ZSBdLCAiYm9vbF90aGVuX2lycnJycnJy
cnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnJy+fn5+flycnJy
cnJycnJycnJycnJycnJycnJycnJycnJyaGVuX3N0cmluZ2xpc3QiOiBbICJ4IiBdLCAic3RyaW5n
X3RoZW5fZGF0ZXRpbWUiOiAi4eEd4eHhjeHh4eHh4eHh4eHhD+Hh4eHh4eHh4eHh4eHh4eHh4eHh
4eHh4eHh4eHh4eHh4f0A////////////////////////Y////zkyMjMzNzIwMzY4NTQ3NzX/AAH/
//9wbGF0Ozg7AGVsdjMyeDQubG9hB2Rfc5CTnoUrCik7AAAJYzQmss/leCIsICJkYXRldGltZV8i
dGhlbl9zdHJpbmciOiAiMTk3MC0wMS0wMVQwMDowMDowMCIsICJkYXRldGltZV90aGVuX2RhdGV0
aW1lIjogIjE5NzBcLzAxXC8wMSAwMDowMDowMCIsICJib29sbGlzdF90aGVuX2Jvb2wiOiBbIHRy
dWUgXSwgImJvb2xsaXN0X3RoZW5faW50IjogWyAxIF0sICJib29sbGlzdF90aGVuX2ludDY0Ijog
WyAxIF0sICJib29sbGlzdF90aGVuX3JlYWwiOiBbIDEuMCBdLCAiYm5fc3RyaW5nbGlzdCI6IFsg
IjAuMDE1NjI1IiBdLCAic3RyaW5nbGlzdF90aGVuX2Jvb2wiOiBbICJ4IiBdLCAic3RyaW5nbGlz
dF90aGVuX2ludCI6IFsgIngiIF0sICJzdHJpbmdsaXN0X3RoZW5faW50NjQiOiBbICJ4IiD5+fn5
+fn5+fldLCAiLAAAAAAAAAAAAAAAAAAAAPn5+fn5+QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHN0cmludHJpbmdsaXN0IjogWyAieCIgXSB9LCDl5eXl
5eXl5SJnZW9tZfn5+XRyeSI6IG51bGz5IPl9Cl3l5eUp5eXlKuXl5eXl5eXl5eXl5eUgCikKfQrl
5eXl5QE=
```

</details>

### Additional contract requirements

`v128.any_true` must return 1 exactly when at least one bit in its input vector is nonzero, and 0 when the input vector is all zero.
