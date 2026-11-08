Support &self shorthand if there is only one extern type in the block
As currently implemented, Rust associated methods and C++ member functions are currently specified with `self: &T` syntax.

```rust
extern "C" {
    type C;
    fn f(self: &C);
}
```

Inside of extern blocks that contain exactly one extern type, we should allow the usual `&self` and `&mut self` shorthand as well.

```rust
extern "C" {
    type C;
    fn f(&self);
}
```
