Type inference failure
```rust

struct A<T>(T);

impl A<i32> {
    fn from(v: i32) -> A<i32> {
        Self(v)
    }
}

fn main() {
    let a = A::from(3);
}
```
The inlay hint shows `A<{unknown}>` for `a`. I'm using ra commit baf832d now.

### Additional contract requirements

The inferred type of `a` in the example must be `A<i32>`; the inlay hint must no longer show `A<{unknown}>`.
