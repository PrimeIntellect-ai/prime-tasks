Containers can't index when key is Vector{Any}
Reported on SO: https://stackoverflow.com/questions/75692147/why-is-my-program-searching-for-this-key

```julia
julia> using JuMP

julia> key = Any[Any["macros", 1], "Outsized_Equipment"]
2-element Vector{Any}:
 Any["macros", 1]
 "Outsized_Equipment"

julia> K = Any[key]
1-element Vector{Any}:
 Any[Any["macros", 1], "Outsized_Equipment"]

julia> model = Model();

julia> @variable(model, x[K])
1-dimensional DenseAxisArray{VariableRef,1,...} with index sets:
    Dimension 1, Any[Any[Any["macros", 1], "Outsized_Equipment"]]
And data, a 1-element Vector{VariableRef}:
 x[Any[Any["macros", 1], "Outsized_Equipment"]]

julia> x[key]
ERROR: KeyError: key "macros" not found
Stacktrace:
```
