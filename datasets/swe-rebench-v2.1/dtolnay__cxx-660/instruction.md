Support elided lifetime in member function receiver
```cpp
// include/example.h

#pragma once
#include <memory>

struct Object {
  void f() const {}
};
```

```rust
// src/main.rs

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("repro/include/example.h");

        type Object<'a>;

        fn f(self: &Object);
    }
}

fn main() {}
```

The above should work (with an elided lifetime on `Object` but currently doesn't.

```console
error[E0726]: implicit elided lifetime not allowed here
 --> src/main.rs:8:21
  |
8 |         fn f(self: &Object);
  |                     ^^^^^^- help: indicate the anonymous lifetime: `<'_>`
```

Writing `fn f(self: &Object<'_>)` instead makes it work but shouldn't be necessary.

Lifetime elision is already support in non-member functions, e.g. `fn f(obj: &Object)`.
