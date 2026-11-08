Support `inline` and `flatten` for generic types
Currently, inlining fails to take the used generic type argument into account:
```rust
struct X<T> {
  t: T
}
struct Y {
  #[ts(inline)]
  x1: X<i32>,
  #[ts(flatten)]
  x2: X<i32>
}
```
