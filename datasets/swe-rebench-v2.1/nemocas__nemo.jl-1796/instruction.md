Error in `absolute_coordinates` method with native prime fields
We have the `absolute_coordinates` method to convert a finite field element to a vector over the prime field corresponding to its internal representation. However while this method is defined for all types of finite field elements, it fails when called on an `fpFieldElem` or an `FpFieldElem` due to a missing `coeff` method for these element types.
```julia
julia> k = Native.GF(7)
Finite field of characteristic 7

julia> a = (k)(3)
3

julia> absolute_coordinates(a)
ERROR: MethodError: no method matching coeff(::fpFieldElem, ::Int64)

Closest candidates are:
  coeff(::QQPolyRingElem, ::Int64)
   @ Nemo ~/.julia/packages/Nemo/0n54t/src/flint/fmpq_poly.jl:53
  coeff(::DualRootSpaceElem, ::Int64)
   @ Oscar ~/.julia/dev/Oscar/experimental/LieAlgebras/src/RootSystem.jl:627
  coeff(::fpAbsPowerSeriesRingElem, ::Int64)
   @ Nemo ~/.julia/packages/Nemo/0n54t/src/flint/nmod_abs_series.jl:76
  ...

Stacktrace:
 [1] absolute_coordinates(x::fpFieldElem)
   @ Hecke ~/.julia/packages/Hecke/gMNzj/src/Misc/RelFiniteField.jl:518
 [2] top-level scope
   @ REPL[4]:1
```
