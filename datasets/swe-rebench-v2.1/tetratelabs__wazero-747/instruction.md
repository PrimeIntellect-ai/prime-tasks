Serialize a compiled module
**Describe the solution you'd like**
Is it possible to replicate [this feature](https://pkg.go.dev/github.com/wasmerio/wasmer-go/wasmer#Module.Serialize) from wasmer-go? Compiling a module results in a significant number of allocations, so I'd like to compile a batch of modules ahead of time to reduce the runtime memory overhead.

### Additional contract requirements

When using a compiler runtime configured with a compilation-cache directory through `experimental.WithCompilationCacheDirName`, compiled module output must be persisted so that later compilations of the same module can reuse it. A module compiled through this workflow must remain usable, including instantiation and calls to its exported functions.
