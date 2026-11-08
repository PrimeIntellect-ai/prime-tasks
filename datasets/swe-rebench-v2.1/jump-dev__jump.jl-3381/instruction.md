Incorrect return type annotations for complex constraints
```julia
julia> using JuMP, HiGHS

julia> model = Model(HiGHS.Optimizer)
A JuMP Model
Feasibility problem with:
Variables: 0
Model mode: AUTOMATIC
CachingOptimizer state: EMPTY_OPTIMIZER
Solver name: HiGHS

julia> @variable(model, x in ComplexPlane())
real(x) + imag(x) im

julia> @constraint(model, c, x == 2 + 3im)
c : real(x) + imag(x) im = (2 + 3im)

julia> optimize!(model)
Running HiGHS 1.5.1 [date: 1970-01-01, git hash: 93f1876e4]
Copyright (c) 2023 HiGHS under MIT licence terms
Presolving model
0 rows, 0 cols, 0 nonzeros
0 rows, 0 cols, 0 nonzeros
Presolve : Reductions: rows 0(-2); columns 0(-2); elements 0(-2) - Reduced to empty
Solving the original LP from the solution after postsolve
Model   status      : Optimal
Objective value     :  0.0000000000e+00
HiGHS run time      :          0.01

julia> value(c)
ERROR: InexactError: Float64(2.0 + 3.0im)
Stacktrace:
 [1] Real
   @ ./complex.jl:37 [inlined]
 [2] convert(#unused#::Type{Float64}, x::ComplexF64)
   @ Base ./number.jl:7
 [3] _constraint_primal(con_ref::ConstraintRef{Model, MathOptInterface.ConstraintIndex{MathOptInterface.ScalarAffineFunction{ComplexF64}, MathOptInterface.EqualTo{ComplexF64}}, ScalarShape}, result::Int64)
   @ JuMP ~/.julia/dev/JuMP/src/constraints.jl:1024
 [4] #value#18
   @ ~/.julia/dev/JuMP/src/constraints.jl:996 [inlined]
 [5] value(con_ref::ConstraintRef{Model, MathOptInterface.ConstraintIndex{MathOptInterface.ScalarAffineFunction{ComplexF64}, MathOptInterface.EqualTo{ComplexF64}}, ScalarShape})
   @ JuMP ~/.julia/dev/JuMP/src/constraints.jl:996
 [6] top-level scope

julia> dual(c)
-0.0

julia> MOI.get(backend(model), MOI.ConstraintDual(), index(c))
-0.0 - 0.0im
```

### Additional contract requirements

For constraints whose function is complex-valued, constraint primal access and dual access must preserve the appropriate complex value type and return the complex results without converting them to real values or raising a conversion error.
