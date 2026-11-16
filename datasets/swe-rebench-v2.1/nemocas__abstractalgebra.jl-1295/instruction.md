no `ngens` for `FreeAssAlgebra`
```julia
julia> A, x = FreeAssociativeAlgebra(QQ, 3)
(Free associative algebra over Rational Field on x1, x2, x3, AbstractAlgebra.Generic.FreeAssAlgElem{fmpq}[x1, x2, x3])

julia> gens(A)
3-element Vector{AbstractAlgebra.Generic.FreeAssAlgElem{fmpq}}:
 x1
 x2
 x3

julia> ngens(A)
ERROR: MethodError: no method matching ngens(::AbstractAlgebra.Generic.FreeAssAlgebra{fmpq})
Closest candidates are:
  ngens(::AbstractAlgebra.Generic.QuotientModule{T}) where T<:RingElement at ~/.julia/packages/AbstractAlgebra/FcxWh/src/generic/QuotientModule.jl:25
  ngens(::Singular.smodule) at ~/.julia/packages/Singular/zLgw5/src/module/module.jl:28
  ngens(::MPolyQuoLocalizedRing) at ~/.julia/packages/Oscar/RlsvY/experimental/Schemes/Auxiliary.jl:343
  ...
Stacktrace:
 [1] top-level scope
   @ REPL[53]:1
```

All similar structures have a `ngens` method, so why not `FreeAssAlgebra`?
