`issparse` is not defined but is requested for a view's parent
**Describe the bug 🐞**

On certain operations, `issparse(::SubArray)` is called, and it calls `issparse` on the parent, but it's not defined in the case of `AbstractVectorOfArray`.

**Expected behavior**

`issparse(::SubArray)` is defined, to `false`.

**Error & Stacktrace ⚠️**

```julia
> U = mapreduce(u -> view(u, :, :), hcat, us)
MethodError: no method matching issparse(::ODESolution{...})
```

**Additional context**

Solution:
```julia
[HIDDEN]
```

### Additional contract requirements

- Calling `issparse` directly on an `AbstractVectorOfArray` must return `false`.
- Calling `issparse` on a `SubArray` view whose parent is an `AbstractVectorOfArray` must return `false` rather than throw.
