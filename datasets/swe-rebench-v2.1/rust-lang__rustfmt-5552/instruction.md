rustfmt eats dyn_star syntax
[Playground](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=4744115d7a207179d93ecba705d16daf)

Given:
```rust
#![feature(dyn_star)]
#![allow(incomplete_features)]

use core::fmt::Debug;

fn main() {
    let i = 42;
    let dyn_i = i as dyn* Debug;
    dbg!(dyn_i);
}
```

This is formatted to:
```rust
#![feature(dyn_star)]
#![allow(incomplete_features)]

use core::fmt::Debug;

fn main() {
    let i = 42;
    let dyn_i = i as Debug;
    dbg!(dyn_i);
}
```

After formatting, this code no longer compiles.
