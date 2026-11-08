Some types don't define check_parent
    julia> check_parent(fmpz(2), fmpz(3))
    ERROR: MethodError: no method matching check_parent(::fmpz, ::fmpz)
    Stacktrace:
     [1] top-level scope at REPL[7]:1

I noticed this because it was missing for qqbar, which breaks generic algorithms:

    julia> R, x = PolynomialRing(QQBar, "x");

    julia> gcd(x^2 - 1, x + 1)
    ERROR: MethodError: no method matching check_parent(::qqbar, ::qqbar)
    Stacktrace:
     [1] gcd(::qqbar, ::qqbar) at /home/fredrik/.julia/dev/AbstractAlgebra/src/Fields.jl:22
     [2] content(::AbstractAlgebra.Generic.Poly{qqbar}) at /home/fredrik/.julia/dev/AbstractAlgebra/src/generic/Poly.jl:2033
     [3] gcd(::AbstractAlgebra.Generic.Poly{qqbar}, ::AbstractAlgebra.Generic.Poly{qqbar}) at /home/fredrik/.julia/dev/AbstractAlgebra/src/generic/Poly.jl:2003
     [4] top-level scope at REPL[11]:1

I guess we're not running into this with fmpz because polynomials will use fmpz_poly instead of generic code, but perhaps other generic code could be affected too?

Should there be a fallback implementation that checks parent(a) == parent(b) for any elements, or should we reimplement this for every type in Nemo?

### Additional contract requirements

Provide a public function `check_parent(a::NCRingElement, b::NCRingElement, throw::Bool=true)` in the `AbstractAlgebra` module. It returns `true` when `parent(a) === parent(b)` and `false` when the parents differ. When the parents differ and `throw` is `true` (the default), it throws an error with the message "Incompatible polynomial rings in polynomial operation". When the parents differ and `throw` is `false`, it returns `false` without throwing.
