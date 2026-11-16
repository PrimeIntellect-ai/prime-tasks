Config in Cargo.toml: invalid type: map, expected a string for key `target.x86_64-unknown-freebsd.image`
### Checklist

- [X] I've looked through the [issues and pull requests](https://github.com/cross-rs/cross/issues?q=) for similar reports

### Describe your issue

Related: https://github.com/cross-rs/cross/issues/657

### What target(s) are you cross-compiling for?

x86_64-unknown-freebsd

### Which operating system is the host (e.g computer cross is on) running?

- [X] macOS
- [ ] Windows
- [ ] Linux / BSD
- [ ] other OS (specify in description)

### What architecture is the host?

- [ ] x86_64 / AMD64
- [ ] arm32
- [X] arm64 (including Mac M1)

### What container engine is cross using?

- [X] docker
- [ ] podman
- [ ] other container engine (specify in description)

### cross version

cross 0.2.4

### Example

```console
$ cargo new foo && cd $_
$ cat <<'EOF' >> Cargo.toml
﻿﻿﻿[package.metadata.cross.target.x86_64-unknown-freebsd]
image.name = "ghcr.io/cross-rs/x86_64-unknown-freebsd:local"
image.toolchain = ["linux/arm64/v8=aarch64-unknown-linux-gnu"]
EOF
$ cross build --target x86_64-unknown-freebsd --release
```

Using cross 0.2.4 from nixpkgs or crates.io, I get:

```
Error:
   0: invalid type: map, expected a string for key `target.x86_64-unknown-freebsd.image`
```

Using cross from `main`, I get a different error:

```console
$ cargo install cross --git https://github.com/cross-rs/cross
$ cross --version
cross 0.2.4 (1d9d310 2023-01-05)
$ cross build --target x86_64-unknown-freebsd --release
Error:
   0: invalid type: string "linux/arm64/v8=aarch64-unknown-linux-gnu", expected a borrowed string for key `target.x86_64-unknown-freebsd.image.toolchain`

Location:
   src/cross_toml.rs:181
```

If I instead put (what I believe to be) the analogous table into `Cross.toml`, I get the same error with nixpkgs and crates.io but it works fine from `main`:

```console
$ cat <<'EOF' > Cross.toml
[target.x86_64-unknown-freebsd]
image.name = "ghcr.io/cross-rs/x86_64-unknown-freebsd:local"
image.toolchain = ["linux/arm64/v8=aarch64-unknown-linux-gnu"]
EOF
$ cross --version
cross 0.2.4 (1d9d310 2023-01-05)
[cross] warning: `cross` does not provide a Docker image for target aarch64-apple-darwin, specify a custom image in `Cross.toml`.
[cross] note: Falling back to `cargo` on the host.
cargo 1.66.0 (d65d197ad 2022-11-15)
$ cross build --target x86_64-unknown-freebsd --release
   Compiling foo v0.1.0 (/private/var/folders/kb/tw_lp_xd2_bbv0hqk4m0bvt80000gn/T/tmp.ililnMNd9D/foo)
    Finished release [optimized] target(s) in 8.52s
```

Using the current `main`, as recommended in the README, is it expected that this table works from `Cross.toml` but not from `Cargo.toml`?

Thanks for your work on a cool project!

### Additional information / notes

_No response_
