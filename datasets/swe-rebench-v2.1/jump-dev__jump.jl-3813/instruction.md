Hygiene issue with indicator constraints
```julia
model = Model()
@variable(model, b, Bin)
@variable(model, x)
@constraint(model, b => {x in MOI.EqualTo(1.0)})
```
gives
```julia
ERROR: LoadError: UndefVarError: `##3910` not defined
Stacktrace:
 [1] macro expansion
   @ ~/.julia/packages/JuMP/W1IDA/src/macros/@constraint.jl:171 [inlined]
 [2] macro expansion
   @ ~/.julia/packages/JuMP/W1IDA/src/macros.jl:393 [inlined]
```
The hygiene seems ok if you do `x == 1` but not with the `in` syntax
