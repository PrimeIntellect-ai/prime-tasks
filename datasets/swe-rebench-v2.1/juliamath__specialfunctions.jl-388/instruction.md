Another gamma_inc_inv failure
After #385 I'm trying to expand the testing of `gamma_inc_inv` and I already hit another case. This is again a case where the original Fortran version also fails.

```julia
julia> a, p, q = 1.0e-20, 1.0, 7.756625260915455e-21
(1.0e-20, 1.0, 7.756625260915455e-21)

julia> gamma_inc_inv(a, p, q)
ERROR: DomainError with -7.70608462508679:
log will only return a complex result if called with a complex argument. Try log(Complex(x)).
Stacktrace:
 [1] throw_complex_domainerror(f::Symbol, x::Float64)
   @ Base.Math ./math.jl:33
 [2] _log(x::Float64, base::Val{:ℯ}, func::Symbol)
   @ Base.Math ./special/log.jl:304
 [3] log
   @ ./special/log.jl:269 [inlined]
 [4] __gamma_inc_inv(a::Float64, minpq::Float64, pcase::Bool)
   @ SpecialFunctions ~/.julia/dev/SpecialFunctions/src/gamma_inc.jl:969
 [5] _gamma_inc_inv
   @ ~/.julia/dev/SpecialFunctions/src/gamma_inc.jl:933 [inlined]
 [6] gamma_inc_inv(a::Float64, p::Float64, q::Float64)
   @ SpecialFunctions ~/.julia/dev/SpecialFunctions/src/gamma_inc.jl:915
 [7] top-level scope
   @ REPL[9]:1
```

### Additional contract requirements

- `gamma_inc_inv(a, p, q)` inverts `gamma_inc(a, x)`: for valid inputs it returns a finite `x` such that `gamma_inc(a, x) ≈ (p, q)`.
- The reported triple `(a, p, q) = (1.0e-20, 1.0, 7.756625260915455e-21)` must return a finite value without throwing.
