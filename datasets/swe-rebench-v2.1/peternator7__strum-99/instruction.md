Use associated constant for EnumCount
Use an associated constant for EnumCount:
```rust
pub trait EnumCount {
    const COUNT: usize;
}
```
This would replace both the `count()` method
https://github.com/Peternator7/strum/blob/a20ee16d6bb0d26c999767e4a9dd7d8ef013c563/strum_macros/src/macros/enum_count.rs#L23
and the `<enum-name>_COUNT` constant
https://github.com/Peternator7/strum/blob/a20ee16d6bb0d26c999767e4a9dd7d8ef013c563/strum_macros/src/macros/enum_count.rs#L29
and it works on stable [since 1.20](https://blog.rust-lang.org/2017/08/31/Rust-1.20.html).

(There is no reason why this needs to be a method (not even a const-fn method), and it's unelegant to have both a method and a non-associated constant.)

An associated constant is the right way to express this.

Related discussion: https://github.com/Peternator7/strum/issues/58 https://github.com/Peternator7/strum/issues/15#issuecomment-372063212

---

Btw, this was motivated by my real-world use case that is currently not possible with `EnumCount`, I need to define the following:
```rust

pub trait Param: From<usize> + Into<usize> + Serialize + DeserializeOwned {
	const PARAM_COUNT: usize;
}

impl<T: From<usize> + Into<usize> + EnumCount> Param for T
where
	[T; <T as EnumCount>::count()]: Serialize + DeserializeOwned,
{
	const PARAM_COUNT: usize = T::count();
}
```
It's not possible because `count()` is not a constant.
