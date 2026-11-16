promote_rule issue with fractions
```julia
S, (x, y) = PolynomialRing(QQ, ["x", "y"])
F = FractionField(S)
R, n = PolynomialRing(F, "n")
poly = x*n+y
```
Then `poly(1)` yields `x+y` and `poly(n)` yields:
```julia
ERROR: MethodError: promote_rule(::Type{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}, ::Type{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}) is ambiguous. Candidates:
  promote_rule(::Type{AbstractAlgebra.Generic.Frac{T}}, ::Type{AbstractAlgebra.Generic.Frac{T}}) where T<:Union{RingElem, AbstractFloat, Integer, Rational} in AbstractAlgebra.Generic at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/generic/Fraction.jl:967
  promote_rule(::Type{AbstractAlgebra.Generic.Frac{T}}, ::Type{U}) where {T<:RingElem, U<:RingElem} in AbstractAlgebra.Generic at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/generic/Fraction.jl:970
[HIDDEN]
Stacktrace:
 [1] promote_rule(::Type{AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}}, ::Type{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}) at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/generic/Poly.jl:2628
 [2] +(::AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}, ::AbstractAlgebra.Generic.Frac{fmpq_mpoly}) at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/Rings.jl:49
 [3] compose(::AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}, ::AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}) at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/generic/Poly.jl:1622
 [4] (::AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}})(::AbstractAlgebra.Generic.Poly{AbstractAlgebra.Generic.Frac{fmpq_mpoly}}) at /Users/ahumenberger/.julia/packages/AbstractAlgebra/RaAkt/src/polysubst.jl:8
 [5] top-level scope at REPL[14]:1
```

### Additional contract requirements

- For the reproduced setup, `poly(n)` should evaluate without a promotion ambiguity error.
