[Needs MOI 0.9.21] AffExpr in ZeroOne does not work
```julia
julia> using JuMP

julia> model = Model()
A JuMP Model
Feasibility problem with:
Variables: 0
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.

julia> @variable(model, x)
x

julia> @constraint(model, x + 1 in MOI.Integer())
ERROR: MethodError: no method matching shift_constant(::MathOptInterface.Integer, ::Float64)
Closest candidates are:
  shift_constant(::Union{EqualTo{T}, GreaterThan{T}, LessThan{T}}, ::T) where T at /home/blegat/.julia/packages/MathOptInterface/C3lip/src/Utilities/sets.jl:39
  shift_constant(::MathOptInterface.Interval, ::Any) at /home/blegat/.julia/packages/MathOptInterface/C3lip/src/Utilities/sets.jl:42
Stacktrace:
 [1] build_constraint(::Function, ::GenericAffExpr{Float64,VariableRef}, ::MathOptInterface.Integer) at /home/blegat/.julia/packages/JuMP/jnmGG/src/macros.jl:491
 [2] top-level scope at /home/blegat/.julia/packages/JuMP/jnmGG/src/macros.jl:621

julia> @constraint(model, x + 1 in MOI.ZeroOne())
ERROR: MethodError: no method matching shift_constant(::MathOptInterface.ZeroOne, ::Float64)
Closest candidates are:
  shift_constant(::Union{EqualTo{T}, GreaterThan{T}, LessThan{T}}, ::T) where T at /home/blegat/.julia/packages/MathOptInterface/C3lip/src/Utilities/sets.jl:39
  shift_constant(::MathOptInterface.Interval, ::Any) at /home/blegat/.julia/packages/MathOptInterface/C3lip/src/Utilities/sets.jl:42
Stacktrace:
 [1] build_constraint(::Function, ::GenericAffExpr{Float64,VariableRef}, ::MathOptInterface.ZeroOne) at /home/blegat/.julia/packages/JuMP/jnmGG/src/macros.jl:491
 [2] top-level scope at /home/blegat/.julia/packages/JuMP/jnmGG/src/macros.jl:621
```
We should probably leave the constant in the function for these sets.

Reported by @jebouchat
