Slicing DenseAxisArrays
```
m = Model()
@defVar(m, x[0:5], Bin)
solve(m)
getValue(x[0])  # Works
getValue(x[0:2])
#BoundsError()
#while loading In[15], in expression starting on line 1
#
# in copy! at array.jl:52
# in getindex at array.jl:265
# in getindex at no file
```

### Additional contract requirements

- Indexing a `JuMP.Containers.DenseAxisArray` with a range or a vector of axis keys along a dimension returns a `DenseAxisArray` slice containing the selected entries, with the selected keys as the corresponding axis labels.
- Indexing with `:` along a dimension returns a slice that keeps that dimension and its axis labels.
- Indexing with a key that is not present in an axis throws a `KeyError`.


- - For a `DenseAxisArray`, `Base.isassigned(A, indices...)` returns `true` when the supplied indices are present on their corresponding axes and `false` when any supplied index is absent.
