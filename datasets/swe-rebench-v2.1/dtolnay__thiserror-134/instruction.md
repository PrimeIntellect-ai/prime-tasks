Lifetimes and #[error(transparent)]
Lifetimes appear to interfere with the use of `#[error(transparent)]`:
```rust
use thiserror::Error;

#[derive(Error, Debug)]
#[error(transparent)]
pub struct Error<'a> {
    inner: ErrorKind<'a>,
}

#[derive(Error, Debug)]
pub enum ErrorKind<'a> {
    #[error("unexpected token: {:?}", .token)]
    Unexpected { token: &'a str },
}
```

```
   Compiling ecl-parser v0.1.0 (/mnt/f/asd/clone/ecl-parse)
error[E0495]: cannot infer an appropriate lifetime due to conflicting requirements
 --> src/bin/lol.rs:3:10
  |
3 | #[derive(Error, Debug)]
  |          ^^^^^
  |
note: first, the lifetime cannot outlive the lifetime `'a` as defined on the impl at 5:18...
 --> src/bin/lol.rs:5:18
  |
5 | pub struct Error<'a> {
  |                  ^^
note: ...so that the types are compatible
 --> src/bin/lol.rs:3:10
  |
3 | #[derive(Error, Debug)]
  |          ^^^^^
  = note: expected `&ErrorKind<'_>`
             found `&ErrorKind<'a>`
  = note: but, the lifetime must be valid for the static lifetime...
note: ...so that the type `ErrorKind<'_>` will meet its required lifetime bounds
 --> src/bin/lol.rs:3:10
  |
3 | #[derive(Error, Debug)]
  |          ^^^^^
  = note: this error originates in a derive macro (in Nightly builds, run with -Z macro-backtrace for more info)

error: aborting due to previous error
```

* rustc 1.46.0 (04488afe3 2020-08-24)
* thiserror 1.0.22
