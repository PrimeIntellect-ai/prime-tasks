Add `expressify` method for `FlintPuiseuxSeriesElem`, replacing its `show` method
As far as I can tell, that's the last remaining user of `show_minus_one`, `needs_parentheses` and `displayed_with_minus_in_front` in Nemo. There is one other in AbstractAlgebra, see https://github.com/Nemocas/AbstractAlgebra.jl/issues/710.

### Additional contract requirements

- Add a public method `AbstractAlgebra.expressify(a::FlintPuiseuxSeriesElem)` that returns a Julia `Expr` which, when evaluated with the series' variable bound, reproduces the series `a`, including its coefficients, its integer and fractional powers, and its truncation `O(...)`.
- Add `Base.show(io::IO, a::FlintPuiseuxSeriesElem)` and `Base.show(io::IO, ::MIME"text/plain", a::FlintPuiseuxSeriesElem)`, each writing the expression-based representation of the series to `io`.
- `coeff(a::FlintPuiseuxSeriesElem, i::Rational)` returns the coefficient of the term with exponent `i`, or the zero element of the coefficient ring when that term is absent.
