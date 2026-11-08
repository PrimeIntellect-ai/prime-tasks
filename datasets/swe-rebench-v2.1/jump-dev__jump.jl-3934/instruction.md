Copy : unsupported subtype of `DenseAxisArray`
Hey,

JuMP threw this warning in one of my projects :

```
┌ Warning: Skipping the copy of object `:in_flow_expr` due to unsupported type JuMP.Containers.DenseAxisArray{Any, 1, Tuple{Vector{Int64}}, Tuple{JuMP.Containers._AxisLookup{Dict{Int64, Int64}}}}. Please open a GitHub issue at https://github.com/jump-dev/JuMP.jl with this message.
```

here is a MRE :

```julia
using JuMP

model = JuMP.Model()

nodes_itr = [1, 2]
arcs_itr = [(1, 2)]

in_arcs = Dict(
    1 => [(1, 2)],
    2 => [],
)

@variable(model, 0 <= arc_flow_var[arc in arcs_itr] <= 10)
@expression(model, in_flow_expr[node in nodes_itr], sum(arc_flow_var[arc] for arc in in_arcs[node]))


model_copy = copy(model)
```

that produces the exact same warning :

```
┌ Warning: Skipping the copy of object `:in_flow_expr` due to unsupported type JuMP.Containers.DenseAxisArray{Any, 1, Tuple{Vector{Int64}}, Tuple{JuMP.Containers._AxisLookup{Dict{Int64, Int64}}}}. Please open a GitHub issue at https://github.com/jump-dev/JuMP.jl with this message.
└ @ JuMP ~/.julia/packages/JuMP/Y2NoH/src/copy.jl:183
```

### Additional contract requirements

Copying a model must also preserve expression values that are plain literals, so that they remain available in the copied model:

- numeric literals of any numeric type (for example `Int`, `Float64`, `BigInt`, or `Complex`),
- string literals,
- symbol literals.

These literal values must remain available in the copied model under the same names.
