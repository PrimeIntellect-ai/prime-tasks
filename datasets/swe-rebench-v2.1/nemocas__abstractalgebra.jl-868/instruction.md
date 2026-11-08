Support residue rings of ZZ[x] with monic modulus
@thofma @fieker

Both Magma and Sage support quotient rings of ZZ[x] by a monic modulus.

Both AbstractAlgebra and Nemo allow creation of the ring, but no operations can be performed due to mod and the like not supporting ZZ[x]. We previously decided they shouldn't, as it's not a Euclidean ring (I think; I am going to start putting decisions we make and their justification in Nemo developer documentation).

Should we allow creation of such residue rings? Should we allow mod and friends to work with ZZ[x] even though it is not Euclidean?

```
julia> R, x = PolynomialRing(ZZ, "x")
(Univariate Polynomial Ring in x over Integers, x)

julia> S = ResidueRing(R, 2x^2 + 1) # Magma rejects this as not monic, Sage rejects as not invertible leading coeff
Residue ring of Univariate Polynomial Ring in x over Integers modulo 2*x^2 + 1

julia> S = ResidueRing(R, x^2 + 1)
Residue ring of Univariate Polynomial Ring in x over Integers modulo x^2 + 1

julia> S(x)
ERROR: MethodError: no method matching mod(::AbstractAlgebra.Generic.Poly{BigInt}, ::AbstractAlgebra.Generic.Poly{BigInt})
Stacktrace:
 [1] (::AbstractAlgebra.Generic.ResRing{AbstractAlgebra.Generic.Poly{BigInt}})(::AbstractAlgebra.Generic.Poly{BigInt}) at /home/wbhart/.julia/dev/AbstractAlgebra/src/generic/Residue.jl:550
 [2] top-level scope at REPL[17]:1
```

### Additional contract requirements

- `ResidueRing(R::AbstractAlgebra.PolyRing, a::RingElement)` constructs the residue ring `R/(a)` and returns a `Generic.ResRing{T}` with `T = elem_type(R)`. This is supported for a monic modulus `a` over `ZZ`.
- For such a residue ring `T`, `modulus(T)` returns the modulus, `isunit(T(x))` reports whether the residue of `x` is a unit, and the default constructors `T()` and `T(1)` produce the zero and one residues.
