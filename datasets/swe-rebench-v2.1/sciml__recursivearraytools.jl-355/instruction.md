`getindex` with slice breaks on size 1 arrays
MWE:

```julia
julia> using SciMLBase

julia> EnsembleSolution(ones(2), 0.0, false, nothing)[:]
2-element Vector{Float64}:
 1.0
 1.0

julia> EnsembleSolution(ones(1), 0.0, false, nothing)[:]
ERROR: MethodError: no method matching reshape(::Float64, ::Int64)

Closest candidates are:
  reshape(::RecursiveArrayTools.AbstractVectorOfArray, ::Any...)
   @ RecursiveArrayTools ~/.julia/packages/RecursiveArrayTools/kqKNI/src/vector_of_array.jl:687
  reshape(::FillArrays.AbstractFill, ::Union{Colon, Integer}...)
   @ FillArrays ~/.julia/packages/FillArrays/oXkMk/src/FillArrays.jl:260
  reshape(::AbstractArray, ::Int64...)
   @ Base reshapedarray.jl:117
  ...

Stacktrace:
 [1] _getindex
   @ ~/.julia/packages/RecursiveArrayTools/kqKNI/src/vector_of_array.jl:278 [inlined]
 [2] getindex(::EnsembleSolution{Float64, 1, Vector{Float64}}, ::Function)
   @ RecursiveArrayTools ~/.julia/packages/RecursiveArrayTools/kqKNI/src/vector_of_array.jl:393
 [3] top-level scope
   @ REPL[13]:1
```

This is because in the following line `reduce(hcat, vecs)` is not type stable: https://github.com/SciML/RecursiveArrayTools.jl/blob/87337d8e13556f5c8877b5a49705c5cce5f08699/src/vector_of_array.jl#L279

However, `Array` seems to work fine:
```julia
julia> Array(EnsembleSolution(ones(1), 0.0, false, nothing))
1-element Vector{Float64}:
 1.0
```
[HIDDEN]

### Additional contract requirements

- All-colon indexing of a singleton numeric vector-of-arrays must succeed and return a one-element array containing its value.
