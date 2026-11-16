Wasmtime: missing trampolines for declarative element segments (should be treated as possibly exported).
### Test Case

Repro to run with `main`:

```rust
use wasmtime::*;

fn main() {
    let engine = Engine::default();

    let module = Module::new(
        &engine,
        r#"(module
        (import "" "callback" (func $callback (param funcref)))
        (elem declare func $f)
        (func $f (param externref))
        (func (export "g")
          (call $callback (ref.func $f))
        )
      )"#,
    )
    .unwrap();

    let store = Store::new(&engine);

    let callback = Func::wrap(&store, |funcref: Option<Func>| {
        funcref
            .unwrap()
            .typed::<Option<ExternRef>, ()>()
            .unwrap()
            .call(Some(ExternRef::new("some data")))
            .unwrap();
    });

    let instance = Instance::new(&store, &module, &[callback.into()]).unwrap();

    let g = instance
        .get_typed_func::<(), ()>("g")
        .unwrap();

    g.call(()).unwrap();

    println!("success!");
}
```

This is a paired down test case that is currently causing the `wasmtime-dotnet` CI to fail.

### Steps to Reproduce

On Windows:

* `cargo new --bin repro`
* `cargo add wasmtime` (change path to local wasmtime repo)
* `cargo run`

### Expected Results

`success!` should be printed.

### Actual Results

Panic due to failure to find trampoline (for signature `(externref) -> ()`, i.e. the funcref passed to `callback`):

```text
thread 'main' panicked at 'trampoline missing', C:\Users\Peter\src\wasmtime\crates\wasmtime\src\store.rs:272:14
stack backtrace:
   0: std::panicking::begin_panic_handler
             at /rustc/2fd73fabe469357a12c2c974c140f67e7cdd76d0\/library\std\src\panicking.rs:493
   1: core::panicking::panic_fmt
             at /rustc/2fd73fabe469357a12c2c974c140f67e7cdd76d0\/library\core\src\panicking.rs:92
   2: core::option::expect_failed
             at /rustc/2fd73fabe469357a12c2c974c140f67e7cdd76d0\/library\core\src\option.rs:1292
   3: core::option::Option<unsafe extern "C" fn(mut wasmtime_runtime::vmcontext::VMContext*, mut wasmtime_runtime::vmcontext::VMContext*, const wasmtime_runtime::vmcontext::VMFunctionBody*, mut u128*)>::expect<unsafe extern "C" fn(mut wasmtime_runtime::vmcontex
             at C:\Users\Peter\.rustup\toolchains\stable-x86_64-pc-windows-msvc\lib\rustlib\src\rust\library\core\src\option.rs:349
   4: wasmtime::store::Store::lookup_trampoline
             at C:\Users\Peter\src\wasmtime\crates\wasmtime\src\store.rs:268
   5: wasmtime::func::Func::from_wasmtime_function
             at C:\Users\Peter\src\wasmtime\crates\wasmtime\src\func.rs:919
   6: wasmtime::func::Func::from_caller_checked_anyfunc
             at C:\Users\Peter\src\wasmtime\crates\wasmtime\src\func.rs:551
   7: wasmtime::func::typed::{{impl}}::from_abi
...
```

### Versions and Environment

Wasmtime version or commit: `main`

Operating system: Windows 10

Architecture: x86-64

### Extra Info

I believe this is caused by #2806.

I think the problem here is that we're failing to determine that `$f` may be possibly exported from the module as the element segment is declarative and not active or passive.  Right now the section translator does nothing for declarative element segments; with the changes from #2806 we should consider all declarative elements as potentially exported functions as the reference might escape the module.

_Note: by changing `$f` to have a signature of `() -> ()`, it runs to completion because it uses the trampoline of `g`._
