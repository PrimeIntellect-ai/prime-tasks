Replacing `backtrace(delegate)` with `backtrace` on a source field
In #109, an idea was raised - is `backtrace(delegate)` needed as a separate attribute?

Its purpose is to signal that another error type will handle the backtrace.  (See https://docs.rs/snafu/0.4.3/snafu/guide/attributes/index.html#controlling-backtraces).  For this to work, that other type, where you add the `backtrace(delegate)` attribute, must be a source field.  And if it's a source field, it can't *directly* be a backtrace field; sources must be other error types, and backtraces must be `Backtrace`.

So, can we simplify and say that backtrace delegation happens by marking a source field with a `backtrace` attribute?

Example with a typical "source" field:

```rust
#[derive(Debug, Snafu)]
enum Error {
    MyError {
        #[snafu(backtrace)]
        source: another::Error,
    },
}
```

Example with a `source` attribute, required to handle another field name:
```rust
#[derive(Debug, Snafu)]
enum Error {
    MyError {
        #[snafu(source, backtrace)]
        my_source: another::Error,
    },
}
```

Source transformation shouldn't be affected; and with #124 (`source(from)` implying `source(true)`) even the most complicated case seems relatively simple:

```rust
#[derive(Debug, Snafu)]
enum Error {
    MyError {
        #[snafu(backtrace)]
        #[snafu(source(from(another::Error, Box::new)))]
        my_source: Box<another::Error>,
    },
}
```

### Additional contract requirements

- If an error variant has both a `backtrace` field and a `backtrace` attribute on a source field, report `Cannot have `backtrace` field and `backtrace` attribute on a source field in the same error variant` for both conflicting fields. The diagnostic for the source field is reported before the diagnostic for the `backtrace` field.
