svdvals! failing for empty matrices
The singular value decompositon fails for empty matrices with element types not `<: BlasFloat`:

```julia
julia> svdvals!(Float16.(ones(10,0)))
ERROR: DimensionMismatch("length of diagonal vector is 0, length of off-diagonal vector is 0")
Stacktrace:
 [1] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:11 [inlined]
 [2] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:17 [inlined]
 [3] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:75 [inlined]
 [4] bidiagonalize!(A::Matrix{Float16})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:269
 [5] svdvals!(A::Matrix{Float16}; tol::Float16, debug::Bool)
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:487
 [6] svdvals!(A::Matrix{Float16})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:487
 [7] top-level scope
   @ REPL[121]:1

julia> svdvals!(BigFloat.(ones(10,0)))
ERROR: DimensionMismatch("length of diagonal vector is 0, length of off-diagonal vector is 0")
Stacktrace:
 [1] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:11 [inlined]
 [2] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:17 [inlined]
 [3] Bidiagonal
   @ /home/julia/julia/usr/share/julia/stdlib/v1.6/LinearAlgebra/src/bidiag.jl:75 [inlined]
 [4] bidiagonalize!(A::Matrix{BigFloat})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:269
 [5] svdvals!(A::Matrix{BigFloat}; tol::BigFloat, debug::Bool)
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:487
 [6] svdvals!(A::Matrix{BigFloat})
   @ GenericLinearAlgebra ~/.julia/packages/GenericLinearAlgebra/JoKjw/src/svd.jl:487
 [7] top-level scope
   @ REPL[122]:1

julia> svdvals!(Float32.(ones(10,0)))
Float32[]
```

### Additional contract requirements

- For `Float16` empty matrices, `svd!` must also return correctly shaped factors: for a `10×0` input, `U` has size `(10, 0)`, `s` is `Float16[]`, and `Vt` has size `(0, 0)`; for a `0×10` input, `U` has size `(0, 0)`, `s` is `Float16[]`, and `Vt` has size `(10, 0)`.
