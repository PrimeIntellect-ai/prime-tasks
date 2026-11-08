Duplicate symbols regression with recent main branch
I've tried rebuilding Rust with the latest main branch, but it regressed and spews out hundreds of duplicate symbols, like here: https://gist.github.com/mati865/312e2a7d2ee0b6f38669315a64db4e6d

Reproduces only when LLVM is built alongside Rust, by editing `config.toml` to:
```
[llvm]
download-ci-llvm = false
```
And running: `PATH=~/Projects/wild:$PATH ./x.py b`

EDIT: [HIDDEN]

### Additional contract requirements

- When building Rust with LLVM built alongside it (`download-ci-llvm = false`), the build must complete without duplicate-symbol errors.
