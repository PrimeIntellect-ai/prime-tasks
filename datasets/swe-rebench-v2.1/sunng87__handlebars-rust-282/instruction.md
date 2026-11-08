Attach custom data to Helper.
Hi!

I'm new to both rust and handlebar-rust, so I'm not quite sure if this is even possible.
Say I want to create a helper that references something else:

```rust
pub struct FooHelper<'a> {
    foo: &'a Foo,
}

let foo = Foo{}
handlebars.register_helper("foo_helper", Box::new(FooHelper{foo: &foo}));
```

This won't work as `register_helper` needs the helper to have `'static` lifetime. Does this mean that I can not attach a reference to the helper? Or maybe this is how it is intended to avoid some behaviors?

Thanks in advance!
