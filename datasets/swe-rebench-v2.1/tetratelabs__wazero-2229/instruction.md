`path_symlink` doesn't work
**Describe the bug**
The `path_symlink` WASI function doesn't seem to work. Always returning `noent` if `-mount dir` doesn't explicitly specify a guest path like `-mount dir:guest`.

**To Reproduce**

Compile this Rust snippet with `wasi` crate v0.11 (for the preview1 API).

```rust
fn main() {
    unsafe {
        let base_fd = 3;

        wasi::path_symlink("file", base_fd, "new-link").unwrap();
    }
}
```

For example:

```
cargo build --target wasm32-wasi
```

And run the produced Wasm binary with Wazero, preopening a directory with a file `file` in it. But don't map it to root.

```
wazero run -mount dir a.wasm
```



**Expected behavior**
Other runtimes like Wasmtime, WasmEdge, Wasmer, and WAMR can handle such a call and create a symlink.

**Environment (please complete the relevant information):**
- Go version: 1.12.1
- wazero Version: d4a49031b671b59fb832c95741df63b96f144104
- Host architecture: amd64
- OS: Darwin
