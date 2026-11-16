Confusing error when a module is found as a file and a directory
When a module is found as both a file `modname.rs` and a directory `modname/mod.rs`, the error from `cargo fmt --all` is wrong and misleading.

Reproduction steps:
```console
cargo new foo --lib
cd foo
echo "mod bar;" > src/lib.rs
touch src/bar.rs
mkdir -p src/bar
touch src/bar/mod.rs
cargo fmt --all
```

Output:
```console
Error writing files: failed to resolve mod `bar`: hi/foo/src does not exist
```

### Additional contract requirements

- When a module is found as both `modname.rs` and `modname/mod.rs`, the reported error must name both candidate files (their paths) so the user can resolve the ambiguity, instead of reporting that the module or its directory does not exist.
