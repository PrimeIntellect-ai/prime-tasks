Give ArrayVec a const-fn constructor
I'm not sure if this is even possible but it would be great if `ArrayVec::new()` would be a `const fn` and hence could be called in places where only constant expressions are allowed (of course behind some feature-flag since const-fn is still unstable).

The reason I'd like this feature is that I work on embedded systems where it's typical to have all memory allocated statically, i.e. for a large buffer one would have something like
```rust
static mut BUFFER: [u8; 4096] = [0; 4096];
```
This works fine for arrays (and Copy types) but it would be great if I could also use an `ArrayVec` there. Again, not sure if it's even possible since `mem::uninitialized()` seems to not be a const-fn (although it should, I think) but maybe/hopefully I'm wrong. :)

`lazy_static!` will not work AFAIK because on first invocation of the initialization code the value gets constructed on the stack which typically will not be large enough to hold that value, even temporarily.

Thanks for considering this! :)

### Additional contract requirements

- `ArrayVec::new()` must be a `const fn` that can be called in constant
  expressions (for example, to initialize a `const` or `static` item).
- `ArrayString::new()` must likewise be a `const fn` that can be called in
  constant expressions.
- Both constructors must be usable without enabling any feature flag; the
  `unstable-const-fn` feature is not required (it may be kept as a no-op).
