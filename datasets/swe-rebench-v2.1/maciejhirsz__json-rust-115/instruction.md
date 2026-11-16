Panic: attempt to subtract with overflow
```rust
extern crate json;
use json::number::Number;

fn main() {
    let n = Number::from_parts(false, 10000000000000000000, -18);
    println!("{}", n);
}
```

```
thread 'main' panicked at 'attempt to subtract with overflow', json-0.11.5/src/util/print_dec.rs:160
```

### Additional contract requirements

- When formatting `Number::from_parts(true, 10_000_000_000_000_000_001, -18)`, the output must be exactly `1.0000000000000000001e+1`.
- When formatting `Number::from_parts(true, 10_000_000_000_000_000_001, -19)`, the output must be exactly `1.0000000000000000001`.
