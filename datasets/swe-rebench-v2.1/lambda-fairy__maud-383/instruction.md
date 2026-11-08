Incorrect expression hygiene results in cryptic errors
Consider the following invocation:

```rust
html! {
  (1 + 1)
}
```

This expands to

```rust
{
    extern crate alloc;
    extern crate maud;
    let mut __maud_output = alloc::string::String::with_capacity(7usize);
    {
        use ::maud::macro_private::*;
        [HIDDEN]
            x => (&&x)
                .implements_render_or_display()
                .render_to(x.0, &mut __maud_output),
        }
    };
    maud::PreEscaped(__maud_output)
}
```

[HIDDEN]

(Also, the String size hint is wrong.)

### Additional contract requirements

- A spliced Rust expression must be evaluated and rendered according to its Rust grouping and operator precedence.
