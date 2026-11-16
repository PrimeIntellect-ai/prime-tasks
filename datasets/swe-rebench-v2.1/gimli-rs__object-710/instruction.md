rustc fails to build with object 0.35+
Building compiler with object updated to 0.35+ on x86_64-unknown-linux-gnu results with
```
  = note: rust-lld: error: /home/user/rust/build/x86_64-unknown-linux-gnu/stage1-std/x86_64-unknown-linux-gnu/release/deps/libpanic_unwind-0a0cf8f8a42e5845.rlib(lib.rmeta): SHT_STRTAB string table section [index 4] is empty
          collect2: error: ld returned 1 exit status
```
see https://github.com/rust-lang/rust/pull/128040

I've bisected object to this https://github.com/gimli-rs/object/pull/646 PR

https://rust-lang.zulipchat.com/#narrow/stream/182449-t-compiler.2Fhelp/topic/compiler.20fails.20to.20build.20with.20object.200.2E35

current master fd84037eb96912392759c70ea7544bb24dd236e1 fails too
