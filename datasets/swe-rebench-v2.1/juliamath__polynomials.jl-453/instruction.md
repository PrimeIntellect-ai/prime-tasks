Error with `Polynomial(Polynomial)`
Iterated polynomial application seems to be broken, but only for Polynomials with different types. MWE:
```
julia> f = Polynomial((1, -1, -1.1))
Polynomial(1 - x - 1.1*x^2)

julia> f(f)
ERROR: MethodError: no method matching one(::Type{Polynomial{Float64, 3}}, ::Int64)

Closest candidates are:
  one(::P, ::Any) where P<:AbstractPolynomial
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/common.jl:781
  one(::Type{P}) where P<:Polynomials.StandardBasisPolynomial
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/polynomials/standard-basis.jl:65
  one(::Type{P}) where P<:AbstractPolynomial
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/common.jl:779
  ...

Stacktrace:
 [1] one(p::Polynomial{Float64, 3}, var::Int64)
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/common.jl:781
 [2] one(p::Polynomial{Float64, 3})
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/common.jl:781
 [3] _one(x::Polynomial{Float64, 3})
   @ Polynomials.EvalPoly ~/.julia/packages/Polynomials/tVgyD/src/contrib.jl:126
 [4] _evalpoly(x::Polynomial{Float64, 3}, p::Vector{Float64})
   @ Polynomials.EvalPoly ~/.julia/packages/Polynomials/tVgyD/src/contrib.jl:56
 [5] evalpoly(x::Polynomial{Float64, 3}, p::Vector{Float64})
   @ Polynomials.EvalPoly ~/.julia/packages/Polynomials/tVgyD/src/contrib.jl:50
 [6] evalpoly(x::Polynomial{Float64, 3}, p::Polynomial{Float64, 3})
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/polynomials/standard-basis.jl:43
 [7] (::Polynomial{Float64, 3})(x::Polynomial{Float64, 3})
   @ Polynomials ~/.julia/packages/Polynomials/tVgyD/src/abstract.jl:122
 [8] top-level scope
   @ REPL[15]:1
```

Also relevant is that this seems to be type-unstable:
```
julia> typeof(f(f))
Polynomial{Any, :x}
```

[HIDDEN]

### Additional contract requirements

- Constructing a polynomial from numeric coefficients of different scalar types must promote them to a common type. Its coefficient element type should reflect that promoted type rather than `Any` when a more specific common type exists.
- Applying a polynomial with mixed-type coefficients to another polynomial must work. The result must retain the promoted coefficient type, and evaluating it at a scalar must agree with nested evaluation (`f(f(x))`).
