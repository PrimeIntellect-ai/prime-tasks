Unimplemented short keyword: '_' when Cargo.toml under path starting with _
### Problem

Since `rust-1.79` we have been unable to build packages that include `build.rs` within our rust workspace with cargo due to the following error.
```
error: failed to determine package fingerprint for build script for foo v0.1.0 (/Users/jemtucker/src/mvp/_code/rust/foo)

Caused by:
  failed to determine the most recently modified file in /Users/jemtucker/src/mvp/_code/rust/foo

Caused by:
  failed to determine list of files in /Users/jemtucker/src/mvp/_code/rust/foo

Caused by:
  Unimplemented short keyword: '_'
```

Our directory structure is as follows.
```
.git/...
_code/rust/Cargo.toml
_code/rust/foo/Cargo.toml
_code/rust/foo/build.rs
_code/rust/foo/src/lib.rs
```

This error occurs when gitoxide is attempting to parse pathspecs of the form `:/_code/rust` and `:!/_code/rust` which are invalid.

[HIDDEN]

### Steps

_No response_

### Possible Solution(s)

_No response_

### Notes

_No response_

### Version

_No response_

### Additional contract requirements

- Cargo must successfully build a package with a build script beneath a repository path component beginning with `_`, including discovering the files needed to determine the build-script fingerprint.
