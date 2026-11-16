Constraint macro modifies expression
```julia
julia> using JuMP

julia> model = Model();

julia> @variable(model, 0 <= x <= 5);

julia> @expression(model, e, x + 5)
x + 5

julia> @constraint(model, -10 <= e <= 10)
x ∈ [-15, 5]

julia> e
x
```
