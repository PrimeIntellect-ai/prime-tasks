Add more flexibility to MetadataCommand
Particularly, I want the ability to run a nightly cargo with some `-Z` commands.  If you want this, when I implement it I'll submit a PR.

### Additional contract requirements

- `MetadataCommand` (in the `cargo_metadata` crate) provides a public method `cargo_path(&mut self, path: impl AsRef<Path>) -> &mut MetadataCommand` that selects the Cargo executable to invoke instead of the default `cargo`. It returns the same builder instance so calls can be chained.
- `MetadataCommand` provides a public method `other_options(&mut self, options: impl AsRef<[String]>) -> &mut MetadataCommand` that forwards the given command-line flags to the `cargo metadata` invocation, so that flags such as `-Z` can be passed to a nightly Cargo. It returns the same builder instance so calls can be chained.
- When the configured Cargo executable does not exist, `exec` returns an error whose kind is `ErrorKind::Io` wrapping an `std::io::Error` with `kind() == std::io::ErrorKind::NotFound`.
