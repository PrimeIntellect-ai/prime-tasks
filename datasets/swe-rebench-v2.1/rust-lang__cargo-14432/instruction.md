warning: output filename collision.
### Problem

Got lots of warnings like below
```
warning: output filename collision.
The lib target `cfg_if` in package `cfg-if v1.0.0` has the same output filename as the lib target `cfg_if` in package `cfg-if v1.0.0`.
Colliding filename is: target/debug/deps/libcfg_if-b07c5e93d2d15f7e.rlib
The targets should have unique names.
Consider changing their names to be unique or compiling them separately.
This may become a hard error in the future; see <https://github.com/rust-lang/cargo/issues/6313>.
```

### Steps

no warnings:
- stable
- cargo 1.81.0-nightly (a515d4634 2024-07-02)

warnings:
- cargo 1.81.0-nightly (154fdac39 2024-07-07) start to pop up warnings.

### Possible Solution(s)

_No response_

### Notes

### Version

```text
nightly-x86_64-apple-darwin
```

### Additional contract requirements

- When Cargo compiles a shared dependency for both the host and the target with different configured rustflags, their outputs must not collide, and Cargo must not emit an output filename collision warning for them.
