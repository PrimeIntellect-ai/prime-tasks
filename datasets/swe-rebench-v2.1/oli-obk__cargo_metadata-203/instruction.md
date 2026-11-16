root_package returns None if no_deps is passed
Minimal Reproducible Example:

`src/main.rs`
```rust
use cargo_metadata::MetadataCommand;

fn main() {
    MetadataCommand::new()
        .exec()
        .unwrap()
        .root_package()
        .expect("root package exists");
    MetadataCommand::new()
        .no_deps()
        .exec()
        .unwrap()
        .root_package()
        .expect("root package exists w/ no_deps called");
}
```

`Cargo.toml`
```toml
[package]
name = "root_package_mre"
version = "0.1.0"
edition = "2021"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[dependencies]
cargo_metadata = "0.15.0"
```

The above crate panics at the second `expect` when run on itself. This is unexpected because there is a clear root crate and the choice to include/exclude dependencies doesn't seem like it should affect its detection.

The [documentation](https://docs.rs/cargo_metadata/0.15.0/cargo_metadata/struct.MetadataCommand.html#method.no_deps) for `MetadataCommand` states "Output information only about the root package", but this is incorrect in the presence of workspaces: I ran into this while loading metadata for [ripgrep](https://github.com/BurntSushi/ripgrep), which at this time has a root package and a workspace. This crate identifies all of the workspace's packages with `no_deps`, running counter to the documentation, though this is almost certainly the correct behavior.

This occurs because `no_deps` leaves `Metadata.resolve` as `None`, and root package detection assumes the resolver will identify the package. I have not yet looked at the raw output of `cargo metadata` and so do not know if there is an alternative way to find the root package.

If this behavior is can't/WONTFIX, a documentation update to `Metadata::root_package` noting this case would be useful.

### Additional contract requirements

- `MetadataCommand::manifest_path(&mut self, path: impl AsRef<Path>) -> &mut MetadataCommand` sets the manifest file that the metadata query reads and returns the same command builder for chaining.
- `Metadata::root_package(&self) -> Option<&Package>` returns the workspace's root package when one can be identified, including when the query was configured with `no_deps`, and returns `None` when no workspace root package can be identified.
- When `no_deps` is used for a workspace, the metadata still includes all of the workspace's packages, not only the root package.
