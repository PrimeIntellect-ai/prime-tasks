Have anyhow::Error implement std::error::Error?
`anyhow::Error` does not implement `std::error::Error`, which leads to confusion when using anyhow with code that expects a `Result<_, std::error::Error>`.

I noticed that the same applies to `failure::Error` in the failure crate.

What is the reason for that? What prevents `anyhow::Error` from implementing `std::error::Error`?

... and thanks for all your awesome Rust crates!

### Additional contract requirements

Add a public conversion `From<anyhow::Error>` for `Box<dyn std::error::Error + 'static>` (equivalently `Box<dyn std::error::Error>`), so that an `anyhow::Error` value can be turned into a boxed `std::error::Error`. This conversion must preserve the original error: the resulting boxed error must report the same message as the original `anyhow::Error` and must own and drop the original error's underlying value. It must also be usable with the `?` operator in a function returning `Result<_, Box<dyn std::error::Error>>`.
