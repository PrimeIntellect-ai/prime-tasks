fmt does not find modules inside inline modules inside non-inline modules
**Problem**
`cargo fmt` does not processes modules that are referenced in an inline mod in a non-inline mod.

This is slightly more complex case than https://github.com/rust-lang/rustfmt/issues/4874, so it seems that bug was not fully fixed.

**Steps**

crate tree:
```
.
├── Cargo.toml
└── src
    ├── foo
    │   └── bar
    │       └── baz.rs
    ├── foo.rs
    └── main.rs
```

`src/main.rs`:
```rust
fn main() {
    println!("Hello, world!");
}

mod foo;
```

`src/foo.rs`:
```rust
mod bar {
    mod baz;
}
```

`src/foo/bar/baz.rs`: empty

1.52.0 is fine:
```
> cargo +1.52.0 fmt -- -v
Formatting /home/jan/x/src/foo/bar/baz.rs
Formatting /home/jan/x/src/foo.rs
Formatting /home/jan/x/src/main.rs
```

1.53.0, stable and nightly are broken:
```
> cargo +1.53.0 fmt -- -v
Formatting /home/jan/x/src/foo.rs
Formatting /home/jan/x/src/main.rs

> cargo +stable fmt -- -v
Formatting /home/jan/x/src/foo.rs
Formatting /home/jan/x/src/main.rs

> cargo +nightly fmt -- -v
Formatting /home/jan/x/src/foo.rs
Formatting /home/jan/x/src/main.rs
```

**Notes**

Output of `rustfmt --version`:
- 1.52.0: `rustfmt 1.4.36-stable (7de6968 2021-02-07)`
- 1.53.0: `rustfmt 1.4.37-stable (2a3635d 2021-05-04)`
- stable: `rustfmt 1.4.37-stable (59eed8a 2021-11-01)`
- nightly: `rustfmt 1.4.38-nightly (baba668 2021-11-03)`

Rust via rustup 1.24.3, Arch Linux.
