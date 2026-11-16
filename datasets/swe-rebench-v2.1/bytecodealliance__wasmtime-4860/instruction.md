Panic compiling modules with NaN constants
On `main`:

```
$ cargo run compile foo.wat
    Finished dev [unoptimized + debuginfo] target(s) in 0.13s
     Running `target/debug/wasmtime compile foo.wat`
thread '<unnamed>' panicked at 'explicit panic', cranelift/codegen/src/scoped_hash_map.rs:125:30
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

with this input:

```wasm
(module
  (func
    i32.const 0
    if  ;; label = @0
      unreachable
    end
    f32.const nan
    drop
  )
)
```

I believe this was introduced in https://github.com/bytecodealliance/wasmtime/pull/4849 (cc @afonso360  and @jameysharp )
