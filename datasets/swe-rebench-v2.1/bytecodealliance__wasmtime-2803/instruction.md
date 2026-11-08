Trap in host function leaks memory, 0.25 regression
### Test Case

```rust
use wasmtime::*;

fn main() {
    let wat = r#"
        (module
            (import "" "" (func $host_hello))
            (memory (export "memory") 0)
            (func (export "hello") call $host_hello)
        )
        "#;
    let big = vec![1; u32::MAX as usize / 8];

    loop {
        let store = Store::default();
        let module = Module::new(store.engine(), wat).unwrap();
        let host_hello = Func::wrap(&store, || -> Result<(), Trap> {
            // If `Ok(())` is returned instead, memory will not leak.
            Err(Trap::new("it's a trap"))
        });
        let instance = Instance::new(&store, &module, &[host_hello.into()]).unwrap();

        // Do a large allocation to speed up memory leak.
        let mem = instance.get_memory("memory").unwrap();
        mem.grow(10_000).unwrap();
        mem.write(0, &big).unwrap();

        let hello = instance.get_typed_func::<(), ()>("hello").unwrap();
        let _ = hello.call(());

        // In wasmtime 0.24, this does not reproduce:
        // let hello = instance.get_func("hello").unwrap().get0::<()>().unwrap();
        // let _ = hello();
    }
}
```

### Steps to Reproduce

Run the above program on Linux x86_64.

### Expected Results

Program can run forever without exhausting system memory.

### Actual Results

Program leaks memory until the system memory is exhausted.

### Versions and Environment

Wasmtime version or commit: 0.25
Operating system: Linux
Architecture:  x86_64

### Extra Info

It does not reproduce on version 0.24, indicating a 0.25 regression. It seems the `Store` is being leaked. This issue was observed in our application as the error `Insufficient resources: mmap failed: Cannot allocate memory (os error 12)`, because the virtual memory space would be exhausted.
