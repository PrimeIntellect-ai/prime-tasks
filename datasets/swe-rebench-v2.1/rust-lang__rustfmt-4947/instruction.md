rustfmt removes GATs from associated type
<!--
Thank you for filing a bug report! 🐛 Please provide a short summary of the bug,
along with any information you feel relevant to replicating the bug.
-->

I tried this code:

```rust
#![feature(generic_associated_types)]

trait GAT {
    type R<T>;
    fn do_something<T>(r: Self::R<T>) -> Self::R<T> {
        r
    }

}
struct SomeStruct;

impl GAT for SomeStruct {
    type R<T> = T;
}

impl SomeStruct {
    fn process<T>(v: T) -> <Self as GAT>::R<T>
    // Issue: rustfmt removes the GAT from the associated R
    where Self: GAT<R<T> = T>
    {
        SomeStruct::do_something(v)
    }
}


fn main() {
  let one: u8 = SomeStruct::process(1);
  assert!(one == 1)
}

```

I expected rustfmt to: *keep `<T>`*
 ```rust
 where Self: GAT<R<T> = T>
 ```

Instead, this happened: *removed `<T>`*
 ```rust
 where Self: GAT<R = T>
 ```
### Meta
<!--
If you're using the stable version of the compiler, you should also check if the
bug also exists in the beta or nightly versions.
-->

`rustc --version --verbose`:
```
rustc 1.56.0-nightly (2f07ae408 2021-08-05)
binary: rustc
commit-hash: 2f07ae408fce782bf1058e3de808f1b6f9ab60a4
commit-date: 2021-08-05
host: x86_64-unknown-linux-gnu
release: 1.56.0-nightly
LLVM version: 12.0.1
```
