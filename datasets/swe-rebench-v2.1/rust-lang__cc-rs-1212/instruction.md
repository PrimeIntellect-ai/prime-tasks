Target strings that end in -none (such as aarch64-unknown-none) should not default to -fPIC
According to the [docs](https://docs.rs/cc/latest/cc/struct.Build.html#method.pic)

> This [pic] option defaults to false for windows-gnu and bare metal targets and to true for all other targets.

This means the bare metal target `aarch64-unknown-none` should default to false, but [HIDDEN]

### Additional contract requirements

- Target strings ending in `-none` must default to PIC disabled; the default GNU command must not add `-fPIC` for such a target.
