Diagnostics request: using variable in variable container bounds
```
using JuMP, SCIP

model = Model(SCIP.Optimizer)

max_a = 10

@variable(model, a, Int)

@variable(model, b[1:a], Int)
# Should have been: @variable(model, b[1:max_a], Int)
```
```
MethodError: no method matching (::Colon)(::Int64, ::VariableRef)

Closest candidates are:
  (::Colon)(::T, ::Any, ::T) where T<:Real
   @ Base range.jl:50
  (::Colon)(::A, ::Any, ::C) where {A<:Real, C<:Real}
   @ Base range.jl:10
  (::Colon)(::T, ::Any, ::T) where T
   @ Base range.jl:49
  ...


Stacktrace:
 [1] macro expansion
   @ ~/.julia/packages/JuMP/027Gt/src/macros.jl:375 [inlined]
 [2] top-level scope
   @ In[2]:6
```

I understand that this does not work, i meant to use `max_a` instead,
but the diagnostic was not as helpful. Might it be possible to improve it perhaps?

### Additional contract requirements

- When a container reference set cannot be evaluated, throw an `ErrorException` whose diagnostic identifies the macro invocation, that reference-set parsing failed, and the offending reference-set expression.
- When a container condition cannot be evaluated, throw an `ErrorException` whose diagnostic identifies the macro invocation, that condition parsing failed, and the offending condition expression.
