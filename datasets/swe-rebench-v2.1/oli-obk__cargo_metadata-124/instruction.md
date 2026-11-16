Expose whether bin/lib target has tests enabled
There currently seems to be no way to figure out if a bin/lib target has tests enabled. Would be great if that information was made available -- I think that is required to solve https://github.com/rust-lang/miri/issues/700.

### Additional contract requirements

- Add a public field `test: bool` to the `Target` struct, accessible directly as `target.test`.
- The field is populated from the `test` key of a target in Cargo JSON metadata output: it is `true` when the target is included in `cargo test` by default and `false` otherwise.
- When the `test` key is absent (Cargo versions older than 1.47), the field defaults to `true`.
