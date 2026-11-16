rust::Fn call with non-const reference argument fails to compile
Repro:

```rust
// src/main.rs

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("example/include/header.h");

        fn call_back(i: &mut i32, f: fn(&mut i32));
    }
}

fn main() {
    let mut i = 0i32;
    ffi::call_back(&mut i, |_| {});
}
```

```cpp
// include/header.h

#pragma once
#include "rust/cxx.h"

inline void call_back(int32_t &i, rust::Fn<void(int32_t &)> f) {
  f(i);
}
```

The build failure is:

```console
In file included from example-f8c8c5261613a040/out/cxxbridge/crate/example/include/header.h:2,
                 from example-f8c8c5261613a040/out/cxxbridge/sources/example/src/main.rs.cc:1:
example-f8c8c5261613a040/out/cxxbridge/include/rust/cxx.h: In instantiation of ‘Ret rust::cxxbridge1::Fn<Ret(Args ...)>::operator()(Args ...) const [with Ret = void; Args = {int&}]’:
example-f8c8c5261613a040/out/cxxbridge/crate/example/include/header.h:5:6:   required from here
example-f8c8c5261613a040/out/cxxbridge/include/rust/cxx.h:478:29: error: cannot bind non-const lvalue reference of type ‘int&’ to an rvalue of type ‘std::remove_reference<int&>::type’ {aka ‘int’}
  478 |   return (*this->trampoline)(std::move(args)..., this->fn);
      |          ~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

[HIDDEN]

### Additional contract requirements

- Invoking a `rust::Fn` with a non-const lvalue-reference argument must compile and pass the referenced object to the callback with reference semantics intact. The callback must be able to access or modify the same object as permitted by the reference type.
