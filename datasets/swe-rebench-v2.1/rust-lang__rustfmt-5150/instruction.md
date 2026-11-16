Rustfmt breaks static async closure
```rust
#![feature(async_closure)]

macro_rules! expr {
    ($e:expr) => {};
}

expr!(static async || {});
```

As of current master (7b8303d47968a0e1fcad4b143e0ff4b5e512f37b), `cargo run --bin rustfmt -- repro.rs --emit=stdout --edition=2021` creates the following diff:

```diff
- expr!(static async || {});
+ expr!(async static || {});
```

which fails to compile:

```console
error: expected one of `move`, `|`, or `||`, found keyword `static`
 --> repro.rs:7:13
  |
4 |     ($e:expr) => {};
  |      ------- while parsing argument for this `expr` macro fragment
...
7 | expr!(async static || {});
  |             ^^^^^^ expected one of `move`, `|`, or `||`
```
