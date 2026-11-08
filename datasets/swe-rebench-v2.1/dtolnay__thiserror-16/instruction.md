Accept `.var` shorthand inside of parens
For example:

```rust
#[derive(Error, Debug)]
pub enum Error {
    #[error("{}", print(.0))]
    Io(io::Error),
}

fn print(error: &io::Error) -> String {
    unimplemented!()
}
```

We should expand `.var` immediately after `(`, not just `,`.
