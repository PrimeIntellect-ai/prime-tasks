Associated type equality constraints interfere with display conversion
The following code fails to compile. Similar code compiles if the associated type's name is different from the struct field's name, although these two things should have no bearing on one another.

```rust
#![allow(non_snake_case)]

use std::fmt::Display;
use std::path::PathBuf;
use thiserror::Error;

trait Trait<T>: Display {
    type A;
}

impl<T> Trait<T> for i32 {
    type A = i32;
}

#[derive(Error, Debug)]
#[error("{A} {b}", b = &0 as &dyn Trait<i32, A = i32>)]
pub struct Error {
    pub A: PathBuf,
}
```

```console
error[E0277]: `PathBuf` doesn't implement `std::fmt::Display`
  --> src/main.rs:16:10
   |
15 | #[derive(Error, Debug)]
   |          ----- in this derive macro expansion
16 | #[error("{A} {b}", b = &0 as &dyn Trait<i32, A = i32>)]
   |          ^^^ `PathBuf` cannot be formatted with the default formatter; call `.display()` on it
   |
   = help: the trait `std::fmt::Display` is not implemented for `PathBuf`
   = note: in format strings you may be able to use `{:?}` (or {:#?} for pretty-print) instead
   = note: call `.display()` or `.to_string_lossy()` to safely print paths, as they may contain non-Unicode data
   = note: this error originates in the macro `$crate::format_args` which comes from the expansion of the derive macro `Error` (in Nightly builds, run with -Z macro-backtrace for more info)
```
