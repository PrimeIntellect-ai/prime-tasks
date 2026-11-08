jump_function ignores coefficient type
@blegat is this expected? I kinda thought that it would return `GenericAffExpr{Float64}`:

```julia
julia> model = Model();

julia> @variable(model, x)
x

julia> f = 1 * index(x) + 2
(2) + (1) MOI.VariableIndex(1)

julia> typeof(f)
MathOptInterface.ScalarAffineFunction{Int64}

julia> jump_function(model, f)
x + 2

julia> typeof(jump_function(model, f))
GenericAffExpr{Int64, VariableRef}
```

### Additional contract requirements

When `jump_function` converts scalar or vector affine or quadratic MOI functions, the resulting JuMP expression coefficients use the promoted type of the model's coefficient type and the MOI function's coefficient type (`promote_type`). This applies to mixed numeric types as well as matching types. Conversion preserves the function's represented terms and constant.
