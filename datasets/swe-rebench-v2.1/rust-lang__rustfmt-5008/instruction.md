formatting removes part of qualified path inside macro
Pretty niche use case, but running `rustfmt` makes the code no longer compile.

```rust
#![feature(more_qualified_paths)]
macro_rules! show {
    ($ty:ty, $ex:expr) => {
        match $ex {
            <$ty>::A(_val) => println!("got a"), // formatting removes <$ty>::
            <$ty>::B => println!("got b"),
        }
    };
}

#[derive(Debug)]
pub enum Enum1 {
    A(u8),
    B,
}

fn main() {
    show!(Enum1, Enum1::B);
}
```

```sh
$ rustfmt --version
rustfmt 1.4.37-nightly (addb4da 2021-09-25)
```
