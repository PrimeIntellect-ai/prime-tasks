BoundsError bug in SVD for zero matrix
I see the following behavior in v0.3.8 (not sure when it started, but this error did not occur before about Dec 5, 2022, the last time I ran Hypatia.jl's test suite):
```
julia> svd(zeros(BigFloat, 2, 2))
ERROR: BoundsError: attempt to access 1-element Vector{BigFloat} at index [0]
Stacktrace:
 [1] setindex!
   @ ./array.jl:966 [inlined]
 [2] svdDemmelKahan!(B::Bidiagonal{BigFloat, Vector{BigFloat}}, n1::Int64, n2::Int64, U::Matrix{BigFloat}, Vᴴ::Matrix{BigFloat})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/ilNvI/src/svd.jl:110
 [3] __svd!(B::Bidiagonal{BigFloat, Vector{BigFloat}}, U::Matrix{BigFloat}, Vᴴ::Matrix{BigFloat}; tol::BigFloat, debug::Bool)
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/ilNvI/src/svd.jl:184
 [4] _svd!(B::Bidiagonal{BigFloat, Vector{BigFloat}}; tol::BigFloat, debug::Bool)
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/ilNvI/src/svd.jl:301
 [5] svd!(A::Matrix{BigFloat}; tol::BigFloat, full::Bool, alg::LinearAlgebra.DivideAndConquer, debug::Bool)
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/ilNvI/src/svd.jl:658
 [6] #svd#114
   @ ~/julia/usr/share/julia/stdlib/v1.8/LinearAlgebra/src/svd.jl:179 [inlined]
 [7] svd(A::Matrix{BigFloat})
   @ LinearAlgebra ~/julia/usr/share/julia/stdlib/v1.8/LinearAlgebra/src/svd.jl:178
 [8] top-level scope
   @ REPL[15]:1
```
