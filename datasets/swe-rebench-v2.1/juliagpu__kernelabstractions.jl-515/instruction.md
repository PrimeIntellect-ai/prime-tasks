Can't allocate empty vector anymore with `KernelAbstractions.zeros`.
With `0.9.23` I get:
```julia
julia> KernelAbstractions.zeros(CPU(), Float32, 0)
ERROR: DivideError: integer division error
Stacktrace:
  [1] div
    @ ./int.jl:295 [inlined]
  [2] div
    @ ./div.jl:308 [inlined]
  [3] div
    @ ./div.jl:353 [inlined]
  [4] fld
    @ ./div.jl:319 [inlined]
  [5] mod
    @ ./int.jl:287 [inlined]
  [6] #4
    @ ~/.julia/packages/KernelAbstractions/QE5mt/src/nditeration.jl:121 [inlined]
  [7] ntuple
    @ ./ntuple.jl:48 [inlined]
  [8] partition
    @ ~/.julia/packages/KernelAbstractions/QE5mt/src/nditeration.jl:119 [inlined]
  [9] partition
    @ ~/.julia/packages/KernelAbstractions/QE5mt/src/KernelAbstractions.jl:644 [inlined]
 [10] launch_config
    @ ~/.julia/packages/KernelAbstractions/QE5mt/src/cpu.jl:83 [inlined]
 [11] (::KernelAbstractions.Kernel{…})(::Vector{…}, ::Vararg{…}; ndrange::Int64, workgroupsize::Nothing)
    @ KernelAbstractions ~/.julia/packages/KernelAbstractions/QE5mt/src/cpu.jl:40
 [12] Kernel
    @ KernelAbstractions ~/.julia/packages/KernelAbstractions/QE5mt/src/cpu.jl:39 [inlined]
 [13] zeros(backend::CPU, ::Type{Float32}, dims::Tuple{Int64})
    @ KernelAbstractions ~/.julia/packages/KernelAbstractions/QE5mt/src/cpu.jl:11
 [14] zeros(backend::CPU, T::Type, dims::Int64)
    @ KernelAbstractions ~/.julia/packages/KernelAbstractions/QE5mt/src/KernelAbstractions.jl:495
 [15] top-level scope
    @ REPL[3]:1
```
