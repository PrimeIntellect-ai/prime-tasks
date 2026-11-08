compiler crash when a variant has duplicate labels in specific circumstance
```gleam
pub type X {
  A
  B(e0: Int, e0: Int)
}

fn compiler_crash(x: X) {
  case x {
    A -> todo
    _ -> todo
  }
}
```

1. One variant has a duplicate field
2. The other variant is used in a pattern match

```rust
Panic: compiler-core/src/exhaustiveness.rs:780
	Custom type variants must exist: Type { name: "X", hint: AlternativeTypes(["UtfCodepoint", "Bool", "Node", "X", "BitArray", "Nil", "Int", "List", "String", "Result", "Float"]) }
Gleam version: 1.5.0
Operating system: linux
```
