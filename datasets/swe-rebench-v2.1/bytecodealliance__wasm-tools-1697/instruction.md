Version where there is "<dash> <only number> <dash>" section cannot be parsed
Code:
```rust
fn main() {
    let mut resolve = wit_parser::Resolve::default();
    resolve.push_str(".", "package documentation:example@1.0.0-11-a;").unwrap();
}

```

Expected: No error
Actual:

```
thread 'main' panicked at src/main.rs:3:72:
called `Result::unwrap()` on an `Err` value: expected ';', found `-`
     --> .:1:39
      |
    1 | package documentation:example@1.0.0-11-a;
      |                                       ^
```

Adding letters before "11" fixes the issue - except then there are dots: `package documentation:example@1.0.0-a1.1-a;` still fails.

EDIT: Another broken package: `package documentation:example@1.0.0-11ab;`

There seems to be issue with mixing numbers with letters
