calling read on 0 dimensional raster fails
Hi! I would have expected `read` to work in the following case:
```julia
someraster = "..."
r = Raster(someraster; lazy=true)
r[X(Near(0)), Y(Near(0)), Band(1)]  # returns value
v = @view r[X(Near(0)), Y(Near(0)), Band(1)]  # returns view and prints nicely
read(v)  # errors with no method matching for copyto! Int16 something deep down in diskarrays
```
I just dug out old code and I think it used to work. Maybe it can be fixed with some code along the lines of:

```julia
function Rasters.read(r::Raster)
    if ndims(r) == 0
        return rebuild(r, first.(r))
    else
        return modify(Array, x)
    end
end

function Rasters.read(r::RasterSeries)
    if ndims(first(r)) == 0
        return rebuild(r, read.(r))
    else
        return modify(Array, x)
    end
end

# sth similar for rasterstack?
```

### Additional contract requirements

This repository is DiskArrays.jl, which does not define `read` for arrays. The
requested behavior corresponds to materializing a zero-dimensional disk array, or a
zero-dimensional view of a disk array, into a concrete `Array`. For a
zero-dimensional `AbstractDiskArray` `a` and its zero-dimensional view `v = view(a)`,
all of the following must succeed and return the stored scalar value:

- `Array(a)[]` and `Array(v)[]`
- `collect(a)[]` and `collect(v)[]`

The same must hold for a zero-dimensional view of a higher-dimensional disk array,
for example `view(a3, 2, 3, 1)` where `a3` is three-dimensional.
