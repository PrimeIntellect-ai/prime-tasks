Add EnumCount derive
I wrote this proc-macro because I needed it (for mapping Enum cases from different enums to Vec regions, making the Vec len equal to the combined number of all cases) and I think it would make sense to include it in this crate, because it already contains many useful derives for enums.
https://github.com/Boscop/enum-count/blob/master/src/lib.rs
https://github.com/Boscop/enum-count-derive/blob/master/src/lib.rs

It allows stuff like [this](https://github.com/Boscop/enum-count/blob/master/examples/basic.rs):
```rust
#[derive(EnumCount)] enum Aa { }

#[derive(EnumCount)]
enum Bb { B0 = AA_COUNT as _ }

#[repr(u8)]
#[derive(EnumCount)]
enum Cc { C0 = AA_COUNT as _, C1 = BB_COUNT as _ }

#[repr(usize)]
#[derive(EnumCount)]
enum Dd { D0 = AA_COUNT, D1 = BB_COUNT, D2 = CC_COUNT }

fn main() {
	println!("{} {} {} {}", Aa::count(), BB_COUNT, Cc::count(), DD_COUNT);
}
```

(The constant is necessary for it to be used in other enums and static array lens etc.)

### Additional contract requirements

- The derive is named `EnumCount` and is used as `#[derive(EnumCount)]`.
- It implements the public trait `strum::EnumCount`, which provides a static method `count()` that takes no arguments and returns `usize`, the total number of variants of the enum.
- For an enum named `MyEnum`, a constant named `MYENUM_COUNT` (the enum name upper-cased with a `_COUNT` suffix) of type `usize` is generated, with the same value as `MyEnum::count()`.
