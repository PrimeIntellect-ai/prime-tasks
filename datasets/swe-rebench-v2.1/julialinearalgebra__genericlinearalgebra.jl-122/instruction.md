Deflation breaks edge case
It seems https://github.com/JuliaLinearAlgebra/GenericLinearAlgebra.jl/pull/108 broke some edge cases.
Consider for instance:
```julia
julia> rank(BigFloat[0 0; 1 -1])
ERROR: MethodError: reducing over an empty collection is not allowed; consider supplying `init` to the reducer
Stacktrace:
  [1] mapreduce_empty(#unused#::typeof(identity), op::Function, T::Type)
    @ Base ./reduce.jl:367
  [2] reduce_empty(op::Base.MappingRF{typeof(identity), typeof(max)}, #unused#::Type{BigFloat})
    @ Base ./reduce.jl:356
  [3] reduce_empty_iter
    @ ./reduce.jl:379 [inlined]
  [4] mapreduce_empty_iter(f::Function, op::Function, itr::SubArray{BigFloat, 1, Vector{BigFloat}, Tuple{UnitRange{Int64}}, true}, ItrEltype::Base.HasEltype)
    @ Base ./reduce.jl:375
  [5] _mapreduce(f::typeof(identity), op::typeof(max), #unused#::IndexLinear, A::SubArray{BigFloat, 1, Vector{BigFloat}, Tuple{UnitRange{Int64}}, true})
    @ Base ./reduce.jl:427
  [6] _mapreduce_dim
    @ ./reducedim.jl:365 [inlined]
  [7] #mapreduce#765
    @ ./reducedim.jl:357 [inlined]
  [8] mapreduce
    @ ./reducedim.jl:357 [inlined]
  [9] #_maximum#783
    @ ./reducedim.jl:999 [inlined]
 [10] _maximum
    @ ./reducedim.jl:999 [inlined]
 [11] #_maximum#782
    @ ./reducedim.jl:998 [inlined]
 [12] _maximum
    @ ./reducedim.jl:998 [inlined]
 [13] #maximum#780
    @ ./reducedim.jl:994 [inlined]
 [14] maximum
    @ ./reducedim.jl:994 [inlined]
 [15] __svd!(B::Bidiagonal{BigFloat, Vector{BigFloat}}, U::Nothing, Vᴴ::Nothing; tol::BigFloat)
    @ GenericLinearAlgebra ~/.julia/dev/GenericLinearAlgebra/src/svd.jl:224
 [16] _svdvals!(B::Bidiagonal{BigFloat, Vector{BigFloat}}; tol::BigFloat)
    @ GenericLinearAlgebra ~/.julia/dev/GenericLinearAlgebra/src/svd.jl:252
 [17] #svdvals!#33
    @ ~/.julia/dev/GenericLinearAlgebra/src/svd.jl:539 [inlined]
 [18] svdvals!(A::Matrix{BigFloat}; tol::BigFloat)
    @ GenericLinearAlgebra ~/.julia/dev/GenericLinearAlgebra/src/svd.jl:567
 [19] svdvals!
    @ ~/.julia/dev/GenericLinearAlgebra/src/svd.jl:564 [inlined]
 [20] svdvals
    @ ~/.julia/juliaup/julia-1.8.5+0.x64.linux.gnu/share/julia/stdlib/v1.8/LinearAlgebra/src/svd.jl:243 [inlined]
 [21] rank(A::Matrix{BigFloat}; atol::Float64, rtol::BigFloat)
    @ LinearAlgebra ~/.julia/juliaup/julia-1.8.5+0.x64.linux.gnu/share/julia/stdlib/v1.8/LinearAlgebra/src/generic.jl:977
 [22] rank(A::Matrix{BigFloat})
    @ LinearAlgebra ~/.julia/juliaup/julia-1.8.5+0.x64.linux.gnu/share/julia/stdlib/v1.8/LinearAlgebra/src/generic.jl:975
 [23] top-level scope
    @ REPL[13]:1
```
[HIDDEN]

### Additional contract requirements

- For the reported matrix, `rank(BigFloat[0 0; 1 -1])` must complete without a deflation-related exception and return its mathematical rank, `1`.
- For a `BigFloat` matrix whose deflation leaves an empty active subproblem, `svdvals(A::AbstractMatrix{T})` must return the complete, mathematically correct singular-value list in descending order, including zero singular values, as a `Vector{T}`, rather than throwing an exception.
