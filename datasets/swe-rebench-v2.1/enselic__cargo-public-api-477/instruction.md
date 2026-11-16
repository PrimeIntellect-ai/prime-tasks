Error if the library target name is different than the package name
## Bug

`cargo public-api` entirely doesn't work if used to check a library on a package with a different name.

Looking at the error, my hypothesis is that the app looks for a concrete rustdoc JSON named _exactly_ the same way as the package, but the name that rustdoc generates is actually the name of the library target.

## Reproduction

1. Create a new lib project

```console
$ cargo new --lib public-api-repro
    Created library `public-api-repro` package
```

2. Change the name of the library target by adding the following to the `Cargo.toml`:

```toml
[lib]
name = "other_name"
```

3. Try to use `cargo-public-api`:
```console
$ cargo public-api
 Documenting public-api-repro v0.1.0 (/home/v0ldek/public-api-repro)
    Finished dev [unoptimized + debuginfo] target(s) in 0.21s
Error: Failed to parse rustdoc JSON at "/home/v0ldek/public-api-repro/target/doc/public_api_repro.json".

This version of `cargo public-api` requires at least:

    nightly-2023-05-24

Ensure your nightly toolchain is up to date with:

    rustup install nightly --profile minimal

If that does not help, it might be `cargo public-api` that is out of date. Try
to install the latest version with

    cargo install cargo-public-api --locked

If the issue remains, please report at

    https://github.com/Enselic/cargo-public-api/issues

Caused by:
    No such file or directory (os error 2)
```

**Note**: after the last step, the `target/doc` directory does contain a file named `other_name.json`.

## Expected behaviour

`cargo-public-api` should recognise the library target name and look for the correct rustdoc file.

## Additional details

Rust version: newest stable, 1.71.0
Rust nightly version: 1.73.0-nightly, 2023-08-02
`cargo-public-api` version: 0.31.2

### Additional contract requirements

- When invoked on the binary-only package named `no-lib`, the command must fail with an error containing `no library targets found in package \`no-lib\``.
