`gamma_inc_inv` throws an DomainError for valid arguments
First observed in https://github.com/JuliaStats/Distributions.jl/issues/1510:

```julia
julia> using SpecialFunctions

julia> gamma_inc_inv(0.010316813105574363, 1-0.010101010101010102, 0.010101010101010102)
ERROR: DomainError with -5.912352019184924:
sqrt will only return a complex result if called with a complex argument. Try sqrt(Complex(x)).
Stacktrace:
 [1] throw_complex_domainerror(f::Symbol, x::Float64)
   @ Base.Math ./math.jl:33
 [2] sqrt
   @ ./math.jl:567 [inlined]
 [3] gamma_inc_inv_qsmall(a::Float64, q::Float64)
   @ SpecialFunctions ~/.julia/packages/SpecialFunctions/9pXme/src/gamma_inc.jl:707
 [4] __gamma_inc_inv(a::Float64, minpq::Float64, pcase::Bool)
   @ SpecialFunctions ~/.julia/packages/SpecialFunctions/9pXme/src/gamma_inc.jl:945
 [5] _gamma_inc_inv
   @ ~/.julia/packages/SpecialFunctions/9pXme/src/gamma_inc.jl:933 [inlined]
 [6] gamma_inc_inv(a::Float64, p::Float64, q::Float64)
   @ SpecialFunctions ~/.julia/packages/SpecialFunctions/9pXme/src/gamma_inc.jl:915
 [7] top-level scope
   @ REPL[12]:1

(jl_j536nH) pkg> st
      Status `/tmp/jl_j536nH/Project.toml`
  [276daf66] SpecialFunctions v2.1.2
```
The same error occurs also in SpecialFunctions 2.0.0, so it wasn't introduced by https://github.com/JuliaMath/SpecialFunctions.jl/pull/377.
