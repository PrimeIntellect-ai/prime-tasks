Bug mutating expression in interval constraint
Found by https://discourse.julialang.org/t/unexpected-behavior-containerized-expression-automatically-redefined-when-included-in-interval-constraint/122648

```Julia
julia> using JuMP

julia> model = Model()
A JuMP Model
├ solver: none
├ objective_sense: FEASIBILITY_SENSE
├ num_variables: 0
├ num_constraints: 0
└ Names registered in the model: none

julia> @variable(model, x)
x

julia> @expression(model, a[1:1], x+1)
1-element Vector{AffExpr}:
 x + 1

julia> a
1-element Vector{AffExpr}:
 x + 1

julia> @constraint(model, -1 <= a[1] <= 1)
x ∈ [-2, 0]

julia> a
1-element Vector{AffExpr}:
 x
```
