Rustfmt loses qself type inside struct expr
```rust
#![feature(more_qualified_paths)]

struct Struct {}

trait Trait {
    type Type;
}

impl Trait for Struct {
    type Type = Self;
}

fn main() {
    let _ = <Struct as Trait>::Type {};
}
```

As of current master (7b8303d47968a0e1fcad4b143e0ff4b5e512f37b), `cargo run --bin rustfmt -- repro.rs --emit=stdout` creates the following diff:

```diff
-     let _ = <Struct as Trait>::Type {};
+     let _ = Trait::Type {};
```

which fails to compile:

```console
error[E0223]: ambiguous associated type
  --> repro.rs:14:13
   |
14 |     let _ = Trait::Type {};
   |             ^^^^^^^^^^^ help: use fully-qualified syntax: `<Type as Trait>::Type`
```
