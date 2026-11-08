Changing workspace Cargo.toml doesn't invalidate build cache for workspace members
### Problem

[The environment variables Cargo sets when building crates](https://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates) don't appear to get updated if the crate's Cargo.toml inherits values from the workspace, and the only change between builds is the value in the workspace's Cargo.toml.

### Steps

```console
% cat >Cargo.toml <<EOF
[workspace]
members = ["lib"]
package.version = "0.2.0"
package.readme = "beep.md"
EOF
% mkdir -p lib/src
% cat >lib/Cargo.toml <<EOF
[package]
name = "lib"
version = "0.1.0"
edition = "2021"
readme = { workspace = true }
EOF
% cat >lib/src/main.rs <<EOF
fn main() {
    println!("Readme: {}", env!("CARGO_PKG_README"));
}
EOF
% cargo run -p lib 2>/dev/null
Readme: ../beep.md
% cat >Cargo.toml <<EOF
[workspace]
members = ["lib"]
package.version = "0.2.0"
package.readme = true
EOF
% # Next command should print ../README.md because the workspace value changed:
% cargo run -p lib 2>/dev/null
Readme: ../beep.md
% # Clearing the cache forces a rebuild, which gives the correct value:
% rm -rf target
% cargo run -p lib 2>/dev/null
Readme: ../README.md
```

### Possible Solution(s)

_No response_

### Notes

_No response_

### Version

```text
cargo 1.79.0 (ffa9cf99a 2024-06-03)
release: 1.79.0
commit-hash: ffa9cf99a594e59032757403d4c780b46dc2c43a
commit-date: 2024-06-03
host: aarch64-apple-darwin
libgit2: 1.7.2 (sys:0.18.3 vendored)
libcurl: 8.1.2 (sys:0.4.72+curl-8.6.0 system ssl:(SecureTransport) LibreSSL/3.3.6)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Mac OS 13.5.2 [64-bit]
```


<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"ranger-ross"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- When a change to the package description makes a build dirty, Cargo's dirty reason must be `the environment variable CARGO_PKG_DESCRIPTION changed`.
- If the source no longer references a changed package-metadata environment variable, the build must remain fresh; verbose output must include `[FRESH] foo v0.1.0 ([ROOT]/foo)`.
- When a change to a referenced package-metadata environment variable makes a build dirty, the dirty reason must be exactly `the environment variable CARGO_PKG_HOMEPAGE changed`, `the environment variable CARGO_PKG_REPOSITORY changed`, `the environment variable CARGO_PKG_LICENSE changed`, `the environment variable CARGO_PKG_LICENSE_FILE changed`, `the environment variable CARGO_PKG_AUTHORS changed`, `the environment variable CARGO_PKG_RUST_VERSION changed`, or `the environment variable CARGO_PKG_README changed`, as applicable.
