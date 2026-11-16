Less memory copies with Memory.MapSlice(offset, []byte)
Folks are doing more work moving data into the memory sandbox addressable by Wasm.

For example, @knqyf263 is working on [structured encoding][1] and @inkeliz is working on [random-access encoding][2]. Structs aside, the problem exists even with strings. You need to pass them into wasm (currently a copy) and its sandbox shouldn't be violated in the process..

Some alternatives solve this by providing unsafe access to the entire memory (ex a []byte). However, doing this breaks the sandbox and also any access controls you may have around boundaries. Furthermore, it may confuse who owns allocation, and typically that's the wasm code itself (ex TinyGo or rust malloc/free functions). Finally, it cements the underlying structure of memory, making changing it, ex [to pages of byte arrays][3], difficult later.

Another way could be to scope a memory overlay, given an offset and a range. For example, you could call an exported function to allocate memory, then apply an overlay which reads from that instead of the underlying source.

```go
var thing []byte = // something to manage in go

// Reserve linear memory using ex TinyGo's allocator.
results, _ := malloc.Call(ctx, len(thing))
ptr := results[0]
defer free.Call(ctx, ptr)

// map the slice so that until unmap is called, any writes to this region are write-through regardless
// of whether it is updated by Go or Wasm. Since this block is after malloc and before free, TinyGo
// shouldn't attempt to clear it.
unmap := mod.Memory().MapSlice(ptr, thing)
defer unmap()
```

Note this pattern could be accomplished many ways. For example if there is global mutable state,
the size could be indicated by a Global which is allocated during an "init" function. The actual
mapping could be done in a host function, which makes it possible to do in a .start function.
Regardless of how this is done, it could allow more precise handing over control of a region to
the host vs exposing the entire memory.

To do this internally may be trickier as there could be many stacks of these layers, so I'm not
entirely sure we want to even do this (think JIT). However, I figured we can think about it a while
and gather feedback about options.

[1]: #523
[2]: https://github.com/tetratelabs/wazero/issues/523#issuecomment-1117634602
[3]: #288

### Additional contract requirements

The following public API details are required in addition to the request above.

- `api.Memory.Read(ctx context.Context, offset, byteCount uint32) ([]byte, bool)` returns a slice that is a view of the underlying memory, not a copy. Writes to the returned slice are visible to Wasm, and writes made by Wasm are visible through the returned slice. The returned slice has capacity equal to `byteCount`, so appending to it allocates a new slice that is no longer shared with the memory. The view stops being shared when the memory's capacity changes, for example when Wasm executes `memory.grow`.

- `wasm.NewMemoryInstance(memSec *wasm.Memory) *wasm.MemoryInstance` in package `github.com/tetratelabs/wazero/internal/wasm` returns a newly allocated memory instance whose `Buffer` has length equal to `memSec.Min` pages and capacity equal to `memSec.Cap` pages (one page is 65536 bytes), and whose `Min`, `Cap`, and `Max` fields are set from `memSec`.
