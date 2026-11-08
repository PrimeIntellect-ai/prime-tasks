Support trailing comma for arg_enum!()
Would be great to support trailing comma for `arg_enum!()` macro, as Rust itself does and this error got me spend a few minutes trying to figure out if I got something (else) wrong in my definition.

Ref: <https://docs.rs/clap/2.27.1/clap/macro.arg_enum.html>


### Rust Version

rustc 1.23.0-nightly (e340996ff 2017-11-02)

### Affected Version of clap

2.27.1

### Expected Behavior Summary

Support trailing comma in `arg_enum!()`, like this:

```rust
arg_enum!{
    #[derive(Debug)]
    pub enum Foo {
        Bar,
        Baz,
        Qux,
    }
}
```

### Actual Behavior Summary

A trailing comma in `enum` definition results in this error:
```
error: no rules expected the token `}`
```

### Steps to Reproduce the issue

Add the above example to a clap app file.

### Sample Code or Link to Sample Code

See above.

### Debug output

N/A
