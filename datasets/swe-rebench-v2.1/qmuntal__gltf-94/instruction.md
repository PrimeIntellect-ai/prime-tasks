Panic when calling modeler.ReadPosition()
By unknown reason blender exported a glb file with some accessors having nil bufferView and Sparse.
Calling modeler.ReadPosition() to read these accessors will cause a panic.
Could it return an error instead?

### Additional contract requirements

- `modeler.ReadAccessor` must return a non-nil slice whenever it returns a nil error. In particular, for an accessor with a nil `BufferView` and nil `Sparse` it returns an empty slice of the accessor's element type (for example `[]float32{}` for a float scalar accessor).
- `modeler.ReadPosition` must not panic when reading an accessor whose `BufferView` is nil. For an accessor with a nil `BufferView` and nil `Sparse` it returns either a non-nil error or an empty result. For an accessor with a nil `BufferView` and non-nil `Sparse` it returns either a non-nil error or the sparse-applied data.
