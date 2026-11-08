Typeshare ignores type annotations in embedded modules
Hi,

I have code like this:

```rust
mod my_module {
    // Types with Typeshare annotations
}
```

...which results in nothing being generated.

If I remove the module around the annotations, everything works.

### Additional contract requirements

Typeshare-annotated types declared in embedded Rust modules must also be included in generated output, including when the declarations are nested inside multiple embedded modules. Types declared outside modules must continue to be generated.
