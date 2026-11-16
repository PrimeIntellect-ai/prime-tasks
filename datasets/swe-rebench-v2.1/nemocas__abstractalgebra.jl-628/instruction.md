divexact does not throw for indivisible elements
```julia
julia> using AbstractAlgebra

julia> R, x = PolynomialRing(AbstractAlgebra.JuliaZZ, "x");

julia> divexact(x^2, x-1)
x+1
```

### Additional contract requirements

- For polynomials over `AbstractAlgebra.JuliaZZ`, `divexact(x^2, x - 1)` must throw an `ArgumentError`.
