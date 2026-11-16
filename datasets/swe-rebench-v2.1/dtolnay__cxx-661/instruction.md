Lifetime doesn't work in pinned member function receiver
```cpp
// include/example.h

#pragma once
#include <memory>

struct Object {
  void f() {}
};
```

```rust
// src/main.rs

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("example/include/example.h");

        type Object<'a>;

        fn f(self: Pin<&mut Object>);
    }
}

fn main() {}
```

The above code should work but currently does not.

```console
error[E0726]: implicit elided lifetime not allowed here
 --> src/main.rs:8:29
  |
8 |         fn f(self: Pin<&mut Object>);
  |                             ^^^^^^- help: indicate the anonymous lifetime: `<'_>`

error[E0308]: mismatched `self` parameter type
 --> src/main.rs:8:20
  |
8 |         fn f(self: Pin<&mut Object>);
  |                    ^^^^^^^^^^^^^^^^ lifetime mismatch
  |
  = note: expected struct `Object<'static>`
             found struct `Object<'_>`
note: the anonymous lifetime #2 defined on the method body at 8:12...
 --> src/main.rs:8:12
  |
8 |         fn f(self: Pin<&mut Object>);
  |            ^^^^^^^^^^^^^^^^^^^^^^^^^
  = note: ...does not necessarily outlive the static lifetime
```

<br>

Various attempted fixes also do not work:

<details>
<summary><code>fn f(self: Pin<&mut Object<'_>>)</code></summary>

```console
error[E0308]: mismatched `self` parameter type
 --> src/main.rs:8:20
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |                    ^^^^^^^^^^^^^^^^^^^^ lifetime mismatch
  |
  = note: expected struct `Object<'_>`
             found struct `Object<'_>`
note: the anonymous lifetime #2 defined on the method body at 8:12...
 --> src/main.rs:8:12
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
note: ...does not necessarily outlive the lifetime `'_` as defined on the impl at 8:36
 --> src/main.rs:8:36
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |                                    ^^

error[E0308]: mismatched `self` parameter type
 --> src/main.rs:8:20
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |                    ^^^^^^^^^^^^^^^^^^^^ lifetime mismatch
  |
  = note: expected struct `Object<'_>`
             found struct `Object<'_>`
note: the lifetime `'_` as defined on the impl at 8:36...
 --> src/main.rs:8:36
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |                                    ^^
note: ...does not necessarily outlive the anonymous lifetime #2 defined on the method body at 8:12
 --> src/main.rs:8:12
  |
8 |         fn f(self: Pin<&mut Object<'_>>);
  |            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```
</details>

<details>
<summary><code> fn f<'a>(self: Pin<&mut Object<'a>>)</code></summary>

```console
error[E0261]: use of undeclared lifetime name `'a`
 --> src/main.rs:8:40
  |
1 | #[cxx::bridge]
  |               - help: consider introducing lifetime `'a` here: `<'a>`
...
8 |         fn f<'a>(self: Pin<&mut Object<'a>>);
  |                                        ^^ undeclared lifetime
  |
  = help: if you want to experiment with in-band lifetime bindings, add `#![feature(in_band_lifetimes)]` to the crate attributes
```
</details>

<br>

This issue might be related to #657 but might be a separate bug because in the case of Pin it won't compile even with a `<'_>` added.
