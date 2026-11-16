Pass-by-reference of shared struct containing String to C++ FFI gives "not FFI-safe" error

`src/main.rs`:

```
#[cxx::bridge(namespace = org::example)]
mod ffi {
    struct SharedThing {
        x: String,
    }

    extern "C" {
        include!("src/demo.h");
        fn do_thing(state: &SharedThing);
    }
}

fn main() {
    let shared = ffi::SharedThing {
        x: "hello".to_string(),
    };
    ffi::do_thing(&shared);
}
```

`src/demo.h`:

```
#pragma once
#include <string>

#include "rust/cxx.h"

namespace org {
namespace example {

struct SharedThing;

void do_thing(const SharedThing& state);

}  // namespace example
}  // namespace org
```

`src/demo.cc`:

```
#include "src/demo.h"

#include <iostream>

#include "src/main.rs.h"

namespace org {
namespace example {

void do_thing(const SharedThing& state) { std::cout << state.x << std::endl; }

}  // namespace example
}  // namespace org
```

`build.rs`:

```
fn main() {
    cxx_build::bridge("src/main.rs")
        .file("src/demo.cc")
        .flag_if_supported("-std=c++14")
        .compile("cxxbridge-demo");

    println!("cargo:rerun-if-changed=src/main.rs");
    println!("cargo:rerun-if-changed=src/demo.h");
    println!("cargo:rerun-if-changed=src/demo.cc");
}
```

`Cargo.toml`:

```
[package]
name = "cxx_test"
version = "0.1.0"
edition = "2018"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[dependencies]
cxx = "0.3"


[build-dependencies]
cxx-build = "0.3"
```

Resulting error:
```
error: `extern` block uses type `std::string::String`, which is not FFI-safe
 --> src/main.rs:9:28
  |
9 |         fn do_thing(state: &SharedThing);
  |                            ^^^^^^^^^^^^ not FFI-safe
  |
note: the lint level is defined here
 --> src/main.rs:1:1
  |
1 | #[cxx::bridge(namespace = org::example)]
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  = help: consider adding a `#[repr(C)]` or `#[repr(transparent)]` attribute to this struct
  = note: this struct has unspecified layout
  = note: this error originates in an attribute macro (in Nightly builds, run with -Z macro-backtrace for more info)

error: aborting due to previous error

error: could not compile `cxx_test`.
```

Changing it to pass-by-value works fine.

Changing `x` to a non-String type also works.
