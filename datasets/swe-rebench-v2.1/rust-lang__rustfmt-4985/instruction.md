Fn params are commented out with doc comments.
```text
$ git rev-parse HEAD
3d8cd57c2f166cb92204e95a5f4c73ab20fed4f2

$ cat example.rs
#[discard_params_doc]
trait Trait {
    fn foo(
        &self,
        /// some docs
        bar: String,
        /// another docs
        baz: i32,
    );
}

$ cargo run --bin rustfmt -- --edition=2018 < example.rs 2> /dev/null
#[discard_params_doc]
trait Trait {
    fn foo(&self, /// some docs bar: String, /// another docs baz: i32
    );
}
```

Normally doc comments on fn params triggers compile error. But it's ok if attribute macro discards it anyway... unless I run rustfmt on it.

### Additional contract requirements

When formatting a function whose parameters have doc comments, keep each parameter syntax outside the line comment so that the comment does not comment out the parameter.
