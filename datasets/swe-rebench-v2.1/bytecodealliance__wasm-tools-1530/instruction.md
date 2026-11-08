wit-component: static Resource function causes Validate to fail
Per the Zulip [discussion](https://bytecodealliance.zulipchat.com/#narrow/stream/206238-general/topic/wasmparser.20assumptions.20about.20Resources.20with.20static.20functions) this afternoon,

this is opened against wasm-tools. The original [issue](https://github.com/bytecodealliance/cargo-component/issues/284), against `cargo-component`, included the zip file to allow easy reproduction of the problem.

The importer.wasm file that is created seems to be the raw wasm file:
[importer.wasm.gz](https://github.com/bytecodealliance/wasm-tools/files/15203467/importer.wasm.gz)

And here is the command line that could reproduce the problem.
```
wasm-tools component new ~/Downloads/importer.wasm --adapt ./wasi_snapshot_preview1.reactor.wasm
```

The error message:
```
error: failed to encode a component from module

Caused by:
    0: failed to validate component output
    1: export name `[static]my-resource.get-static` is not valid
       static resource name is not known in this context (at offset 0xb)
```
