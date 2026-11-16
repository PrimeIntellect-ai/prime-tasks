Stop returning MA.Zero() from expressions
```julia
using JuMP, MutableArithmetics
m = Model()
@variable(m, x>=0)
@constraint(m,
     [x, MutableArithmetics.Zero()] in MOI.SOS1([1.0, 2.0])
 )

ERROR: At REPL[20]:1: `@constraint(m, [x, MutableArithmetics.Zero()] in MOI.SOS1([1.0, 2.0]))`: unable to add the constraint because we don't recognize Any[x, MutableArithmetics.Zero()] as a valid JuMP function.
Stacktrace:
 [1] error(::String, ::String)
   @ Base ./error.jl:42
 [2] _macro_error(macroname::Symbol, args::Vector{Any}, source::LineNumberNode, str::String)
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:1280
 [3] (::JuMP.var"#_error#83"{Symbol, LineNumberNode})(str::String)
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:548
 [4] build_constraint(_error::JuMP.var"#_error#83"{Symbol, LineNumberNode}, func::Vector{Any}, set::MathOptInterface.SOS1{Float64})
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:375
 [5] macro expansion
   @ ~/.julia/packages/JuMP/MIPb6/src/macros.jl:608 [inlined]
 [6] top-level scope
   @ REPL[20]:1

```

My use case is not actually putting `MutableArithmetics.Zero()` into the SOS constraint, but a variable is getting set to `MutableArithmetics.Zero()` by some other means (in JuMP I assume).
