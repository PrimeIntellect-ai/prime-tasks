Panicks at match arm that starts with non-ascii char
```rust
enum NonAscii {
    Abcd,
    Éfgh,
}

use NonAscii::*;

fn f(x: NonAscii) -> bool {
    match x {
        Éfgh => true,
        _ => false,
    }
}

fn main() {
    dbg!(f(Abcd));
}
```

Rustfmt on Playground (1.4.37-nightly (2021-06-12 24bdc6d)) fails to format the above code:
```
thread 'main' panicked at 'byte index 109 is not a char boundary; it is inside 'É' (bytes 108..110) of `enum NonAscii {
    Abcd,
    Éfgh,
}

use NonAscii::*;

fn f(x: NonAscii) -> bool {
    match x {
        Éfgh => true,
        _ => false,
    }
}

fn main() {
    dbg!(f(Abcd));
}
`', src/tools/rustfmt/src/visitor.rs:47:15
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```
