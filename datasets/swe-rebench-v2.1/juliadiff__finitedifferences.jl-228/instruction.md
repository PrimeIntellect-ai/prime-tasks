Argument limited to Functions
FiniteDifferences does not support objects that can be called without being a subtype of `Function`. It's a bit weird since Julia does not support multiple inheritances. [HIDDEN] If not it would be good to discuss the issue/workaround in the README.

```julia
using Interpolations
f = linear_interpolation(1:10, 1:10)
central_fdm(5, 1)(x -> f(x), 1.5)
# 1.000000000000018
central_fdm(5, 1)(f, 1.5)
#ERROR: MethodError: no method matching (::FiniteDifferences.AdaptedFiniteDifferenceMethod{5, 1, FiniteDifferences.UnadaptedFiniteDifferenceMethod{7, 5}})(::Interpolations.Extrapolation{Float64, 1, ScaledInterpolation{Float64, 1, Interpolations.BSplineInterpolation{Float64, 1, Vector{Float64}, BSpline{Linear{Throw{OnGrid}}}, Tuple{Base.OneTo{Int64}}}, BSpline{Linear{Throw{OnGrid}}}, Tuple{UnitRange{Int64}}}, BSpline{Linear{Throw{OnGrid}}}, Throw{Nothing}}, ::Float64)
#Closest candidates are:
#  (::FiniteDifferences.AdaptedFiniteDifferenceMethod)(::TF, ::Real) where TF<:Function
#   @ FiniteDifferences ~/.julia/packages/FiniteDifferences/zZFW0/src/methods.jl:191
#  (::FiniteDifferences.AdaptedFiniteDifferenceMethod{P, Q})(::TF, ::Real, ::Real) where {P, Q, TF<:Function}
#   @ FiniteDifferences ~/.julia/packages/FiniteDifferences/zZFW0/src/methods.jl:238
```

### Additional contract requirements

- Finite-difference methods must accept callable objects that are not subtypes of `Function`, provided they can be called with a numeric argument, and return derivative estimates for them as they do for ordinary functions.
