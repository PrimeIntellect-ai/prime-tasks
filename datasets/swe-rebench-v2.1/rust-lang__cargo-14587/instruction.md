Precedence of `cargo rustc -- <flags>`  is too low to override flags set by Cargo
<sup>**Original issue title:** `-C strip=symbols` doesn't work like `strip = true`</sup>

### Problem

Reproducer: https://github.com/konstin/strip-reproducer/blob/main/compile.sh

With the default linker on linux, passing `-C link-arg=-s`, `-C strip=symbols` and `-C strip=debuginfo` to `cargo rustc` all don't strip the binary properly as setting `strip = true` does, even though the [docs](https://doc.rust-lang.org/cargo/reference/profiles.html#strip) say "The strip option controls the [-C strip flag](https://doc.rust-lang.org/rustc/codegen-options/index.html#strip)".

In [maturin](https://github.com/PyO3/maturin) we expose a `--strip` option, since small size is important for publishing. We pass this on to `cargo rustc`, historically with `-C link-arg=-s`, but i also tried with `-C strip=symbols`. This does strip some debuginfo, 40MB -> 37MB in the case of uv, but not down to 30MB for the fully stripped binary (https://github.com/astral-sh/uv/issues/5683). In the minimal reproducer, only `strip = true` shows any effect.

Note that this only happens with the default linker, mold strips properly in both cases.

### Steps

https://github.com/konstin/strip-reproducer/blob/main/compile.sh

Create a new project with `cargo new strip-reproducer`, then run:

```bash
cargo build -q --release
echo "Release: $(stat --printf="%s" target/release/strip-reproducer)"

cargo rustc -q --release -- -C strip=symbols
echo "strip=symbols: $(stat --printf="%s" target/release/strip-reproducer)"

cargo rustc -q --release -- -C strip=debuginfo
echo "strip=debuginfo: $(stat --printf="%s" target/release/strip-reproducer)"

printf "[profile.release]\nstrip = true\n" >> Cargo.toml
cargo build -q --release
echo "strip = true: $(stat --printf="%s" target/release/strip-reproducer)"
```

```
Release: 398360
strip=symbols: 398360
strip=debuginfo: 398360
strip = true: 334304
```

### Possible Solution(s)

There should ideally be a cli option to strip like `strip = true` does, or the docs should be adjusted on the differences between `strip = true` and the `-C` options.

### Notes

_No response_

### Version

```text
cargo 1.80.0 (376290515 2024-07-16)
release: 1.80.0
commit-hash: 37629051518c3df9ac2c1744589362a02ecafa99
commit-date: 2024-07-16
host: x86_64-unknown-linux-gnu
libgit2: 1.7.2 (sys:0.18.3 vendored)
libcurl: 8.6.0-DEV (sys:0.4.72+curl-8.6.0 vendored ssl:OpenSSL/1.1.1w)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Ubuntu 24.4.0 (noble) [64-bit]
```

### Additional contract requirements

The reported precedence problem must be resolved behaviourally: `cargo rustc -- <flags>` must be able to override flags that Cargo itself sets for the compilation. Specifically, on nightly Cargo (when nightly features are allowed) the trailing `cargo rustc -- <flags>` arguments are placed after the flags Cargo generates from the profile and other internal settings, so that a later `-C strip=...` from the command line wins over the profile-derived `-C strip=...`. The trailing arguments remain lower precedence than the `build.rustflags` family (for example the `RUSTFLAGS` environment variable), which keeps the highest precedence.

This higher-precedence behaviour is gated on nightly features being allowed. On stable Cargo, and when the environment variable `__CARGO_RUSTC_ORIG_ARGS_PRIO` is set to the value `1`, the previous (lower) precedence is used: the trailing `cargo rustc -- <flags>` arguments are placed before the flags Cargo generates from the profile.

Concretely, for a release build invoked as `cargo rustc --release -v -- --cfg cargo_rustc -C strip=symbols` with `RUSTFLAGS=--cfg from_rustflags`, the `[RUNNING]` rustc invocation on nightly must contain, in order, the profile-derived `-C strip=debuginfo`, then `--cfg cargo_rustc -C strip=symbols`, then `--cfg from_rustflags`. With `__CARGO_RUSTC_ORIG_ARGS_PRIO=1`, or on stable, the order must instead be `--cfg cargo_rustc -C strip=symbols`, then `-C strip=debuginfo`, then `--cfg from_rustflags`.
