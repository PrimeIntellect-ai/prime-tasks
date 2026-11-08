Evaluation of UnivPoly
Hi!
While working with the universal polynomials I encountered an unexpected error with one of the methods of `evaluate`. Here are the steps to reproduce:
```
julia> using AbstractAlgebra

julia> S=UniversalPolynomialRing(ZZ)
Universal Polynomial Ring over Integers

julia> x,y=gens(S, ["x", "y"])
(x, y)

julia> evaluate(x, [1], [y])
ERROR: Cannot promote to common type
Stacktrace:
 [1] promote(x::AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}, y::AbstractAlgebra.Generic.MPoly{BigInt})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ZmWFo/src/NCRings.jl:56
 [2] *(x::AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}, y::AbstractAlgebra.Generic.MPoly{BigInt})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ZmWFo/src/NCRings.jl:78
 [3] __evaluate(a::AbstractAlgebra.Generic.MPoly{BigInt}, vars::Vector{Int64}, vals::Vector{AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}}, powers::Vector{Dict{Int64, AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}}})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ZmWFo/src/MPoly.jl:923
 [4] _evaluate(a::AbstractAlgebra.Generic.MPoly{BigInt}, S::AbstractAlgebra.Generic.MPolyRing{BigInt}, R::AbstractAlgebra.Integers{BigInt}, vars::Vector{Int64}, vals::Vector{AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ZmWFo/src/MPoly.jl:901
 [5] evaluate(a::AbstractAlgebra.Generic.MPoly{BigInt}, vars::Vector{Int64}, vals::Vector{AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/ZmWFo/src/MPoly.jl:870
 [6] evaluate(a::AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}, vars::Vector{Int64}, vals::Vector{AbstractAlgebra.Generic.UnivPoly{BigInt, AbstractAlgebra.Generic.MPoly{BigInt}}})
   @ AbstractAlgebra.Generic ~/.julia/packages/AbstractAlgebra/ZmWFo/src/generic/UnivPoly.jl:850
 [7] top-level scope
   @ REPL[4]:1

julia> evaluate(x, [1], [0])
0

julia> typeof(evaluate(x, [1], [0]))
AbstractAlgebra.Generic.MPoly{BigInt}

julia> evaluate(x, [y, y])
y
```

Plugging in integers seems to work fine although the return type is not what I would expect. The actual problem occurs when one tries to plug in a polynomial into one variable. Even though it is possible to plug in the same polynomial into the same variable using the method that plugs in a whole vector of elements.

### Additional contract requirements

- Calling `evaluate` on a universal polynomial with a vector of variable indices and a vector of values must return an element of the same universal polynomial ring as the input, including when the values are plain integers or ring elements of the base ring (the result must not be a multivariate polynomial over the base ring).
- Substituting a universal polynomial of that ring into one of the variables through the same method must be supported and must return an element of that ring.
