Is it possible to grow api.Memory programmatically?
There are scenarios where we may grow shared memory programmatically:

```go
module, _ := v.runtime.InstantiateModuleFromCode(ctx, policy)
module.Memory().Grow(1) // error: unresolved reference 'Grow'
```

However, the `Grow` method is not defined on the `api.Memory` interface. It's only defined on the internal `MemoryInstance` struct:

```go
func (m *MemoryInstance) Grow(newPages uint32) (result uint32) {
	// [...]
}
```

Is it intentionally designed like that, or there is another API to grow shared memory?

### Additional contract requirements

- The `api.Memory` interface in package `github.com/tetratelabs/wazero/api` exposes a method `Grow(ctx context.Context, deltaPages uint32) (previousPages uint32, ok bool)`. It grows the memory by `deltaPages` pages (65536 bytes per page) and returns the number of pages before the growth. When the requested growth would exceed the memory maximum, it returns `ok == false` and leaves the memory size unchanged.
- The `MemoryInstance.Grow` method has the same signature `Grow(ctx context.Context, delta uint32) (previousPages uint32, ok bool)` and the same behaviour.
