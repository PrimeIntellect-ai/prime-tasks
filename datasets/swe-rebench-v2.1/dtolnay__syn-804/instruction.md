Parse const underscore in traits
As seen in https://github.com/rust-lang/rust/blob/8aa9d2014f4e5258f83b907e8431c59a33acdae7/src/test/ui/parser/assoc-const-underscore-syntactic-pass.rs#L10.

```rust
pub trait A {
    const _: () = ();
}
```

Rustc accepts this syntactically but not semantically.
