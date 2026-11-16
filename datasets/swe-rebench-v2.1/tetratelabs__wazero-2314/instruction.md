Running into `wasm error: indirect call type mismatch` when using the compiler backend, but not the interpreter
**Describe the bug**
I am running a wasm module that uses `call_indirect` - when using the interpreter it runs successfully, but when using the compiler it fails with `wasm error: indirect call type mismatch` - it also runs successfully on wasmtime, so I think this could be a compiler bug.

**To Reproduce**
I've uploaded the wasm here: [wasm.zip](https://github.com/user-attachments/files/16985989/wasm.zip)

Then using the extism CLI: https://github.com/extism/cli/ (can be installed by cloning the repo and running `go install ./extism` from the root of the repo)
```
EXTISM_ENABLE_WASI_OUTPUT=1 extism call ./plugin.wasm req --allow-host '*' --input "https://extism.org" --wasi --link import_module=import_module.wasm --log-level info
```

Note: the current CLI uses wazero 1.7, but I've also tested using the latest code on `main` with the same result.

**Expected behavior**
The call should return successfully instead of throwing the type mismatch error

**Environment (please complete the relevant information):**
- Go version: 1.22.6
- wazero Version:tested on 1.7 and the latest main (`58488880a334e8bda5be0d715a24d8ddeb34c725`)
- Host architecture: amd64
- Runtime mode: compiler

**Additional context**
[HIDDEN]

### Additional contract requirements

A valid module that imports a function through another module and calls it indirectly must execute successfully with the compiler backend.
