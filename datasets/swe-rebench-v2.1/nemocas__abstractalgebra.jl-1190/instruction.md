Broken ad hoc operations for fractions
```
julia> R, x = PolynomialRing(ZZ, "x")
(Univariate Polynomial Ring in x over Integers, x)

julia> x//2
x//2

julia> x//2 + 2//3
ERROR: InexactError: BigInt(4//3)
Stacktrace:
 [1] Integer
   @ ./rational.jl:110 [inlined]
 [2] convert
   @ ./number.jl:7 [inlined]
 [3] setindex!(A::Vector{BigInt}, x::Rational{BigInt}, i1::Int64)
   @ Base ./array.jl:843
 [4] setcoeff!
   @ ~/.julia/dev/AbstractAlgebra/src/generic/Poly.jl:33 [inlined]
 [5] *(a::Rational{Int64}, b::AbstractAlgebra.Generic.Poly{BigInt})
   @ AbstractAlgebra ~/.julia/dev/AbstractAlgebra/src/Poly.jl:770
 [6] *
   @ ~/.julia/dev/AbstractAlgebra/src/Poly.jl:778 [inlined]
 [7] +(a::AbstractAlgebra.Generic.Frac{AbstractAlgebra.Generic.Poly{BigInt}}, b::Rational{Int64})
   @ AbstractAlgebra ~/.julia/dev/AbstractAlgebra/src/Fraction.jl:320
 [8] top-level scope
   @ REPL[28]:1
```

### Additional contract requirements

- For both ordinary fraction elements (`FracElem`) and factored fractions (`FactoredFrac`), arithmetic with `Rational` values must follow the usual ordered arithmetic semantics for `+`, `-`, and `*`, in either operand order. A rational need not be representable as an element of the fraction’s coefficient ring for the operation to be valid.
- `divexact` must support a fraction and a `Rational` in either operand order whenever the quotient is defined, returning a fraction representing that quotient.
