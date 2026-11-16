Rustfmt breaks match arm starting with attributed block
If a match arm starts with a block with an attribute, rustfmt removes the brackets, resulting in code that cannot compile.

Before rustfmt:

```rust
match () {
        _ => {
            #[cfg(debug_assertions)]
            {
                println!("Foo");
            }
        }
    }

    match () {
        _ => {
            #[allow(unsafe_code)]
            unsafe {}
        }
    }
```

After rustfmt:

```rust
match () {
        _ =>
        #[cfg(debug_assertions)]
        {
            println!("Foo");
        }
    }

    match () {
        _ =>
            #[allow(unsafe_code)]
            unsafe {}
    }
```

Which results in the attributes being placed in invalid positions.

```rust
error[E0658]: attributes on expressions are experimental
 --> src\main.rs:6:9
  |
6 |         #[cfg(debug_assertions)]
  |         ^^^^^^^^^^^^^^^^^^^^^^^^
  |
  = note: for more information, see https://github.com/rust-lang/rust/issues/15701

error: removing an expression is not supported in this position
 --> src\main.rs:6:9
  |
6 |         #[cfg(debug_assertions)]
  |         ^^^^^^^^^^^^^^^^^^^^^^^^

error[E0658]: attributes on expressions are experimental
  --> src\main.rs:14:13
   |
14 |             #[allow(unsafe_code)]
   |             ^^^^^^^^^^^^^^^^^^^^^
   |
   = note: for more information, see https://github.com/rust-lang/rust/issues/15701

error: aborting due to 3 previous errors
```

I assume it's related to blocks, as the following code is not changed by rustfmt:

```rust
match () {
    _ => {
        #[cfg(debug_assertions)]
        println!("Foo");
    }
}
```

-----

rustfmt 1.4.11-stable (9eb4b564 2020-01-29)
rustfmt 1.4.12-nightly (9f53665f 2020-02-10)
