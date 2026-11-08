Error defining element of polynomial ring over polynomial ring over `AcbField`
This works fine (over `QQ`):

```julia
using Nemo
R, t = polynomial_ring(QQ, "t")
D, Dt = polynomial_ring(R, "Dt")
A_scalarform = t^3*(32*t^2-1)*(32*t^2+1)*Dt^4+2*t^2*(7168*t^4-3)*Dt^3+t*(55296*t^4-7)*Dt^2+(61440*t^4-1)*Dt+12288*t^3
```

This does not work fine (over `AcbField`):

```julia
using Nemo
CC = AcbField(32)
R, t = polynomial_ring(CC, "t")
D, Dt = polynomial_ring(R, "Dt")
A_scalarform = t^3*(32*t^2-1)*(32*t^2+1)*Dt^4+2*t^2*(7168*t^4-3)*Dt^3+t*(55296*t^4-7)*Dt^2+(61440*t^4-1)*Dt+12288*t^3
```

Here is the error message:

```
ERROR: MethodError: promote_rule(::Type{acb_poly}, ::Type{acb_poly}) is ambiguous.

Candidates:
  promote_rule(::Type{T}, ::Type{T}) where T<:NCRingElement
    @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/49QmB/src/NCRings.jl:28
  promote_rule(::Type{acb_poly}, ::Type{T}) where T
    @ Nemo ~/.julia/packages/Nemo/6KhBr/src/arb/acb_poly.jl:777

[HIDDEN]

Stacktrace:
 [1] promote_rule(#unused#::Type{AbstractAlgebra.Generic.Poly{acb_poly}}, #unused#::Type{acb_poly})
   @ AbstractAlgebra.Generic ~/.julia/packages/AbstractAlgebra/49QmB/src/generic/Poly.jl:330
 [2] promote_rule_sym(#unused#::Type{AbstractAlgebra.Generic.Poly{acb_poly}}, #unused#::Type{acb_poly})
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/49QmB/src/NCRings.jl:31
 [3] try_promote
   @ ~/.julia/packages/AbstractAlgebra/49QmB/src/NCRings.jl:41 [inlined]
 [4] promote(x::AbstractAlgebra.Generic.Poly{acb_poly}, y::acb_poly)
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/49QmB/src/NCRings.jl:52
 [5] +(x::AbstractAlgebra.Generic.Poly{acb_poly}, y::acb_poly)
   @ AbstractAlgebra ~/.julia/packages/AbstractAlgebra/49QmB/src/NCRings.jl:66
 [6] afoldl(::typeof(+), ::AbstractAlgebra.Generic.Poly{acb_poly}, ::AbstractAlgebra.Generic.Poly{acb_poly}, ::acb_poly)
   @ Base ./operators.jl:536
 [7] +(::AbstractAlgebra.Generic.Poly{acb_poly}, ::AbstractAlgebra.Generic.Poly{acb_poly}, ::AbstractAlgebra.Generic.Poly{acb_poly}, ::AbstractAlgebra.Generic.Poly{acb_poly}, ::acb_poly)
   @ Base ./operators.jl:578
 [8] top-level scope
   @ REPL[5]:1
```

The "possible fix" suggested by Julia does not seem helpful.

### Additional contract requirements

Evaluating the displayed nested polynomial expression over `AcbField` succeeds without a promotion ambiguity.
