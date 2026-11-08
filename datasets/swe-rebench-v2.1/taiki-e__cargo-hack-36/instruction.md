`--remove-dev-deps` does not work properly without subcommand
This is a regression due to https://github.com/taiki-e/cargo-hack/commit/12534df1509e4a2a20749288f81414bedbdcacec.

If there is no subcommand then all packages will be skipped:

https://github.com/taiki-e/cargo-hack/blob/6d2227259fb0dd4495c583983f54198084a27453/src/package.rs#L30-L35

https://github.com/taiki-e/cargo-hack/blob/6d2227259fb0dd4495c583983f54198084a27453/src/package.rs#L46

### Additional contract requirements

- Running `--remove-dev-deps` without a subcommand must process package manifests and remove their dev-dependencies; it must not skip every package.
- When a private crate is skipped, stderr must include `skipped running on private crate <name>` (for example, `skipped running on private crate real`).
