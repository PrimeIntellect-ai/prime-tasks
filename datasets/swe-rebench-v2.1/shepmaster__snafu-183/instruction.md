`ensure` doesn't play well with opaque errors
Combining opaque error types with `ensure` doesn't really work well.

`fail` returns a `Result<T, Error>`, and with opaque errors, `Error` will be the private `ExampleInnerError`, so the final type is incompatible with `Result<T, ExamplePublicError>`

`ensure` merely returns what `fail` does, which as far as I can tell, makes it unusable in a public API.

Maybe it'd make sense for `ensure` to do something like [HIDDEN] instead?

Example

```rust
#[derive(Debug, Snafu)]
pub struct ExamplePublicError(ExampleInnerError);

#[derive(Debug, Snafu)]
enum ExampleInnerError {
    ExampleError {},
}

type ExampleResult<T, E = ExamplePublicError> = std::result::Result<T, E>;

pub fn example() -> ExampleResult<()> {
    ensure!(false, ExampleError);
    return ExampleError.fail();
	// return [HIDDEN] // Works
}
```

Output:

```
error[E0308]: mismatched types
   --> src/lib.rs:154:5
    |
153 | pub fn example() -> ExampleResult<()> {
    |                     ----------------- expected `std::result::Result<(), crate::ExamplePublicError>` because of return type
154 |     ensure!(false, ExampleError);
    |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ expected struct `crate::ExamplePublicError`, found enum `crate::ExampleInnerError`
    |
    = note: expected type `std::result::Result<(), crate::ExamplePublicError>`
               found type `std::result::Result<_, crate::ExampleInnerError>`
    = note: this error originates in a macro outside of the current crate (in Nightly builds, run with -Z external-macro-backtrace for more info)
```

### Additional contract requirements

- When the predicate passed to `ensure!` fails, the selected error must be usable as the enclosing function’s declared error type, including when that type is an opaque public error type.
