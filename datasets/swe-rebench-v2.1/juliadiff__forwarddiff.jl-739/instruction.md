UpperTriangular / LowerTriangular broken on 1.0.0
MWE:

```julia
using ForwardDiff, LinearAlgebra
ForwardDiff.gradient(sum, UpperTriangular(randn(3, 3)))
```

On v0.10.38

```julia
julia> ForwardDiff.gradient(sum, UpperTriangular(randn(3, 3)))
3×3 UpperTriangular{Float64, Matrix{Float64}}:
 1.0  1.0  1.0
  ⋅   1.0  1.0
  ⋅    ⋅   1.0
```

On v1.0.0

```julia
julia> ForwardDiff.gradient(sum, UpperTriangular(randn(3, 3)))
ERROR: ArgumentError: cannot set index in the lower triangular part (2, 1) of an UpperTriangular matrix to a nonzero value (Dual{ForwardDiff.Tag{typeof(sum), Float64}}(0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0))
Stacktrace:
  [1] throw_nonzeroerror(T::Type, x::Any, i::Int64, j::Int64)
    @ LinearAlgebra ~/.julia/juliaup/julia-1.11.4+0.aarch64.apple.darwin14/share/julia/stdlib/v1.11/LinearAlgebra/src/triangular.jl:295
  [2] setindex!
    @ ~/.julia/juliaup/julia-1.11.4+0.aarch64.apple.darwin14/share/julia/stdlib/v1.11/LinearAlgebra/src/triangular.jl:306 [inlined]
  [3] _unsafe_setindex!
    @ ./reshapedarray.jl:297 [inlined]
  [4] setindex!
    @ ./reshapedarray.jl:286 [inlined]
  [5] setindex!
    @ ./subarray.jl:372 [inlined]
  [6] macro expansion
    @ ./broadcast.jl:973 [inlined]
  [7] macro expansion
    @ ./simdloop.jl:77 [inlined]
  [8] copyto!
    @ ./broadcast.jl:972 [inlined]
  [9] copyto!
    @ ./broadcast.jl:925 [inlined]
 [10] materialize!
    @ ./broadcast.jl:883 [inlined]
 [11] materialize!
    @ ./broadcast.jl:880 [inlined]
 [12] seed!(duals::UpperTriangular{…}, x::UpperTriangular{…}, seeds::NTuple{…})
    @ ForwardDiff ~/ppl/ForwardDiff.jl/src/apiutils.jl:52
 [13] vector_mode_dual_eval!(f::typeof(sum), cfg::ForwardDiff.GradientConfig{…}, x::UpperTriangular{…})
    @ ForwardDiff ~/ppl/ForwardDiff.jl/src/apiutils.jl:23
 [14] vector_mode_gradient(f::typeof(sum), x::UpperTriangular{…}, cfg::ForwardDiff.GradientConfig{…})
    @ ForwardDiff ~/ppl/ForwardDiff.jl/src/gradient.jl:91
 [15] gradient
    @ ~/ppl/ForwardDiff.jl/src/gradient.jl:20 [inlined]
 [16] gradient(f::typeof(sum), x::UpperTriangular{…}, cfg::ForwardDiff.GradientConfig{…})
    @ ForwardDiff ~/ppl/ForwardDiff.jl/src/gradient.jl:17
 [17] gradient(f::typeof(sum), x::UpperTriangular{Float64, Matrix{Float64}})
    @ ForwardDiff ~/ppl/ForwardDiff.jl/src/gradient.jl:17
 [18] top-level scope
    @ REPL[2]:1
Some type information was truncated. Use `show(err)` to see complete types.
```

I think this is caused by #695 and the fact that `iszero(ForwardDiff.Dual(0.0, 1.0))` no longer returns true, so the checks here fail https://github.com/JuliaLang/LinearAlgebra.jl/blob/aecb71426201bad8447be446589d3af986886a87/src/triangular.jl#L295-L304
