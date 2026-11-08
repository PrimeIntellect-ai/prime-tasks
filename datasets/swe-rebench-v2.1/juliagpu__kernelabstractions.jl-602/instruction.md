`StackOverflowError` on `get_backend(::UnitRange)`
MRE:

```
julia> using KernelAbstractions # v0.9.34

julia> get_backend(1:3)
ERROR: StackOverflowError:
Stacktrace:
 [1] get_backend(A::UnitRange{Int64}) (repeats 79984 times)
   @ KernelAbstractions C:\Users\konin_bt\.julia\packages\KernelAbstractions\sWSE0\src\KernelAbstractions.jl:519
```

I can imagine that trying to obtain the backend of an `UnitRange` is not a useful thing to do, but this probably still isn't desirable behavior.

This issue looks similar to https://github.com/JuliaGPU/KernelAbstractions.jl/issues/366.

### Additional contract requirements

Calling `get_backend` on a `UnitRange` must terminate without producing a `StackOverflowError`.
