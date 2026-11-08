const generics support
Consider the following code. It currently does not compile (on version 1.0.0).

```rs
#[auto_impl::auto_impl(&)]
trait Foo {
    fn foo<const I: i32>(&self);
}

fn main() {}
```

Using `cargo expand` I believe the macro expands to:
```rs
impl<'a, T: 'a + Foo + ?::core::marker::Sized> Foo for &'a T {
    fn foo<const I: i32>(&self) {
        [HIDDEN]
    }
}
```

[HIDDEN]

### Additional contract requirements

- For a trait method with a const generic parameter, the generated reference implementation must forward calls with the corresponding const argument, so the shown example compiles.
