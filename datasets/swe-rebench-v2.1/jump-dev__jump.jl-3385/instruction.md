Generic numeric type in JuMP
MOI parameterizes function and set types with the number type used to store the data, example:

```julia
julia> using JuMP
julia> MOI.LessThan(big"3.5")
MathOptInterface.LessThan{BigFloat}(3.5)
```

For the moment, JuMP uses and assumes `Float64`:
```julia
julia> @variable(m, x[1:3])
julia> @constraint(m, sum(x) <= 1//7)
x[1] + x[2] + x[3] ≤ 0.14285714285714285
```

Julia-native solvers should support more numeric types (see https://github.com/JuliaOpt/Convex.jl/issues/262#issuecomment-515522868), using them through JuMP would in the current state block this genericity.

From the user perspective, generic number types could allow chosen precision, Unitful.jl and others
