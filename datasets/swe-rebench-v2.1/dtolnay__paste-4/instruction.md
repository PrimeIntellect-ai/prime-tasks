Pasted identifier may not refer to a captured local variable
This is a consequence of hygiene rules.

```rust
extern crate paste;

fn main() {
    let yy = 0;

    paste::expr! {
        println!("{}", [<y y>]);
    }
}
```

```console
error[E0425]: cannot find value `yy` in this scope
 --> src/main.rs:6:5
  |
6 | /     paste::expr! {
7 | |         println!("{}", [<y y>]);
8 | |     }
  | |_____^ not found in this scope
```

### Additional contract requirements

An identifier formed by pasting tokens inside `paste::expr!` must resolve to a local variable in the lexical scope where the expression is written. A same-named item in an enclosing module must not take precedence over that local binding.
