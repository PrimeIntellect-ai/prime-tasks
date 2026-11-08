Rustfmt creates invalid syntax on extern block containing macro call
```rust
macro_rules! x {
    ($tt:tt) => {};
}

extern "C" {
    x!(-);
    x!(x);
}
```

Rustfmt loses the necessary `;` after *some* macro calls, which becomes invalid Rust syntax in the above input. The call `x!(x);` appears unaffected, regardless of the order of the two calls.

```diff
-     x!(-);
+     x!(-)
```

Self-contained repro as of current master (e0c7b7d5d30d5b47f9d6a9fd3c449fc610a330b9):

```console
$ echo 'extern { x!(-); x!(x); }' | cargo run --bin rustfmt
extern "C" {
    x!(-)
    x!(x);
}

$ !! | rustc -
error: macros that expand to items must be delimited with braces or followed by a semicolon
 --> <anon>:2:7
  |
2 |     x!(-)
  |       ^^^
  |
help: change the delimiters to curly braces
  |
2 |     x!{-}
  |       ~ ~
help: add a semicolon
  |
2 |     x!(-);
  |          +
```
