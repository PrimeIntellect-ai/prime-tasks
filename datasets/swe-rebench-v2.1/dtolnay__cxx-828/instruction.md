Undeclared lifetime when function pointer argument contains lifetime from extern signature
Repro:

```rust
// src/main.rs

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("example/include/header.h");

        fn call_back<'a>(i: &'a i32, f: fn(&'a i32));
    }
}

fn main() {
    let i = 0i32;
    ffi::call_back(&i, |_| {});
}
```

```cpp
// include/header.h

#pragma once
#include "rust/cxx.h"

inline void call_back(const int32_t &i, rust::Fn<void(const int32_t &)> f) {
  f(i);
}
```

```console
error[E0261]: use of undeclared lifetime name `'a`
 --> src/main.rs:6:45
  |
1 | #[cxx::bridge]
  |               - lifetime `'a` is missing in item created through this procedural macro
...
6 |         fn call_back<'a>(i: &'a i32, f: fn(&'a i32));
  |                                             ^^ undeclared lifetime
  |
  = note: for more information on higher-ranked polymorphism, visit https://doc.rust-lang.org/nomicon/hrtb.html
  = help: if you want to experiment with in-band lifetime bindings, add `#![feature(in_band_lifetimes)]` to the crate attributes
help: consider making the type lifetime-generic with a new `'a` lifetime
  |
6 |         fn call_back<'a>(i: &'a i32, f: for<'a> fn(&'a i32));
  |                                         ^^^^^^^
```
