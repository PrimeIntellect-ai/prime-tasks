Error on trailing comma
The following code compiles:

```rust
#[auto_impl::auto_impl(&)]
trait MyTrait<T> {}
```

But the following code gives an error:

```rust
#[auto_impl::auto_impl(&)]
trait MyTrait<T,> {}
```

```
error: expected one of `#`, `>`, `const`, identifier, or lifetime, found `,`
 --> src/main.rs:3:1
  |
3 | #[auto_impl::auto_impl(&)]
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^ expected one of `#`, `>`, `const`, identifier, or lifetime
  |
  = note: this error originates in the attribute macro `auto_impl::auto_impl` (in Nightly builds, run with -Z macro-backtrace for more info)
```

This is a problem when the formatter inserts trailing commas, which happens if you have lots of generics so that they wrap over to a new line:

```rust
#[auto_impl::auto_impl(&)]
trait MyTrait<
    A,
    B,
    C,
    D,
> {}
```
