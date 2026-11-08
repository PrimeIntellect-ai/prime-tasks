all_constraints(model)
**Is your feature request related to a problem? Please describe.**
I wish to list all constraints so i can then check all `shadow_prices` so I can find which as nonzero to determine which constraints are binding.
I have also wanted to list all constraints for check feasibility of a potential primal solution in the past, but that is now a inbuilt feature of JuMP so i don't need to.

**Describe the solution you'd like**
define
```julia
[HIDDEN]
```
in JuMP and export it

**Describe alternatives you've considered**
Not doing this, and making the user do this

### Additional contract requirements

- Define a public function `all_constraints(model::Model; include_variable_in_set_constraints::Bool)::Vector{ConstraintRef}` in JuMP and export it. The keyword argument `include_variable_in_set_constraints` is required.
- When `include_variable_in_set_constraints = true`, the returned vector includes constraints that arise from variable set membership (such as bounds and integrality). When `include_variable_in_set_constraints = false`, only structural constraints (linear, conic, and nonlinear) are returned.
- The returned vector contains every applicable constraint of the model, including linear, conic, and nonlinear constraints.
