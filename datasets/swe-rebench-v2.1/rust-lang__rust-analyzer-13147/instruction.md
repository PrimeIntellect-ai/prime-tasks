`try_into` from custom trait misresolved for prelude `TryInto` in 2021 edition
# Environment
rust 1.56.1
rust-analyzer 2021-11-01
edition 2021

# Steps to reproduce
```rust
pub struct GreaterThanZero(i32);

impl TryFrom<i32> for GreaterThanZero {
    type Error = &'static str;

    fn try_from(value: i32) -> Result<Self, Self::Error> {
        Ok(GreaterThanZero(value))
    }
}

pub trait MyTrait {
    // This has the same name as `TryInto::try_into`
    fn try_into(&self, addition: i32) -> Result<GreaterThanZero, ()>;
}

impl MyTrait for i32 {
    fn try_into(&self, addition: i32) -> Result<GreaterThanZero, ()> {
        Ok(GreaterThanZero(*self + addition))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internal() {
        let a: &dyn MyTrait = &2;
        let v: GreaterThanZero = (&*a).try_into(1).unwrap();
        assert_eq!(3, v.0);
    }
}
```
* Expected: No error. `try_into` in `internal()` resolves to `MyTrait::try_into`
* What happened:  cargo compiles fine but RA reports `mismatched-arg-count`. `try_into` in `internal()` resolves to `TryInto::try_into` from the prelude.

Courtesy of [minstrel1977@rustcc](https://rustcc.cn/article?id=d093f682-f2c2-4121-933f-b4c0bc5ff8ca)

### Additional contract requirements

- When a method is called on a value whose type is a trait object type `dyn Trait`, or on a value whose type is a type parameter `T` bounded by `Trait`, a method declared by `Trait` (or one of its supertraits) takes priority over a method of the same name declared by any other trait that is in scope. In particular, given `trait Trait { fn into(&self) -> usize }`, a call `a.into()` where `a: &dyn Trait` or `a: &T` with `T: Trait` resolves to `Trait::into` and has type `usize`.
