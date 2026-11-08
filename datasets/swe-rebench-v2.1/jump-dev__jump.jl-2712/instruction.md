Improve error for Interval constraints with non-constant set
https://github.com/jump-dev/JuMP.jl/pull/2574 didn't help our error reporting for interval constraints with non-constant sets.

We should really say

```Julia
julia> @constraint(model, x <= 2x <= 3x)
ERROR: At REPL[5]:1: `@constraint(model, x <= 2x <= 3x)`: Interval constraint
contains non-constant left- or right-hand sides. Reformulate as two separate
constraints.
```

## 0.21.7

```Julia
model = Model()
@variable(model, x)

julia> @constraint(model, x <= 2x <= 3x)
ERROR: At REPL[5]:1: `@constraint(model, x <= $(Expr(:escape, 2)) * $(Expr(:escape, :x)) <= $(Expr(:escape, 3)) * $(Expr(:escape, :x)))`: Expected x to be a number.
Stacktrace:
 [1] error(::String, ::String)
   @ Base ./error.jl:42
 [2] _macro_error(macroname::Symbol, args::Vector{Any}, source::LineNumberNode, str::String)
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:1280
 [3] (::JuMP.var"#_error#83"{Symbol, LineNumberNode})(str::String)
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:548
 [4] build_constraint(_error::JuMP.var"#_error#83"{Symbol, LineNumberNode}, expr::AffExpr, lb::VariableRef, ub::AffExpr)
   @ JuMP ~/.julia/packages/JuMP/MIPb6/src/macros.jl:494
 [5] macro expansion
   @ ~/.julia/packages/JuMP/MIPb6/src/macros.jl:608 [inlined]
 [6] top-level scope
   @ REPL[5]:1
```

## 0.21.8

```Julia
model = Model()
@variable(model, x)

julia> @constraint(model, x <= 2x <= 3x)
ERROR: At REPL[179]:1: `@constraint(model, x <= $(Expr(:escape, 2)) * $(Expr(:escape, :x)) <= $(Expr(:escape, 3)) * $(Expr(:escape, :x)))`: Unrecognized constraint building format. Tried to invoke `build_constraint(error, 2 x, x, 3 x)`, but no such method exists. This is due to specifying an unrecognized function, constraint set, and/or extra positional/keyword arguments.

If you're trying to create a JuMP extension, you need to implement `build_constraint` to accomodate these arguments.
Stacktrace:
 [1] error(::String, ::String)
   @ Base ./error.jl:42
 [2] _macro_error(macroname::Symbol, args::Tuple{Symbol, Expr}, source::LineNumberNode, str::String)
   @ JuMP ~/.julia/packages/JuMP/Xrr7O/src/macros.jl:1365
 [3] (::JuMP.var"#_error#92"{Tuple{Symbol, Expr}, Symbol, LineNumberNode})(str::String)
   @ JuMP ~/.julia/packages/JuMP/Xrr7O/src/macros.jl:588
 [4] build_constraint(_error::JuMP.var"#_error#92"{Tuple{Symbol, Expr}, Symbol, LineNumberNode}, func::AffExpr, set::VariableRef, args::AffExpr; kwargs::Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}})
   @ JuMP ~/.julia/packages/JuMP/Xrr7O/src/macros.jl:406
 [5] build_constraint(_error::Function, func::AffExpr, set::VariableRef, args::AffExpr)
   @ JuMP ~/.julia/packages/JuMP/Xrr7O/src/macros.jl:402
 [6] macro expansion
   @ ~/.julia/packages/JuMP/Xrr7O/src/macros.jl:677 [inlined]
 [7] top-level scope
   @ REPL[179]:1
```
