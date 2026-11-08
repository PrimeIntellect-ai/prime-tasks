Add empty! for all Heaps
I would like an `empty!` method for all heap types. It is currently only defined for `BinaryMinMaxHeap`.

Compared to using `extract_all!`, an `empty!` method would not allocate a vector, which might be important for performance oriented applications.

Maybe an implementation could look like this:

```jl
[HIDDEN]
```

### Additional contract requirements

- `empty!(h)` must be available for every heap type and remove all elements, leaving `h` empty.
- `empty!(h)` returns the same heap object after removing all of its elements.
- Clearing a heap must not allocate an extracted-elements vector.
- For `BinaryHeap` and `MutableBinaryHeap`, `empty!(h)` must allocate zero bytes.
