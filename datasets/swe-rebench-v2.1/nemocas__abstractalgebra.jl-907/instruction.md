zero(f::PolyElem) is producing elements with the wrong parent
From https://github.com/oscar-system/Oscar.jl/pull/469:

```julia
julia> Qx, x = PolynomialRing(QQ, "x", cached = false)
(Univariate Polynomial Ring in x over Rationals, x)

julia> parent(zero(x)) === parent(x)
false
```

I don't think this is intented.

Edit: Thanks @tthsqe12.
