Iterating SparseAxisArray does not preserve order
x-ref https://discourse.julialang.org/t/unexpected-jump-variable-order-when-indexed-by-tuple/110262

```julia
julia> using JuMP

julia> model = Model();

julia> N = 1:2;

julia> M = [[1.0, 11.0, 100.0], [0.0, 17.0, 104.0]];

julia> @variable(model, foo[n in N, M[n]])
JuMP.Containers.SparseAxisArray{VariableRef, 2, Tuple{Int64, Float64}} with 6 entries:
  [1, 1.0  ]  =  foo[1,1.0]
  [1, 100.0]  =  foo[1,100.0]
  [1, 11.0 ]  =  foo[1,11.0]
  [2, 0.0  ]  =  foo[2,0.0]
  [2, 104.0]  =  foo[2,104.0]
  [2, 17.0 ]  =  foo[2,17.0]

julia> foo.data
Dict{Tuple{Int64, Float64}, VariableRef} with 6 entries:
  (2, 17.0)  => foo[2,17.0]
  (1, 11.0)  => foo[1,11.0]
  (1, 1.0)   => foo[1,1.0]
  (1, 100.0) => foo[1,100.0]
  (2, 0.0)   => foo[2,0.0]
  (2, 104.0) => foo[2,104.0]

julia> @constraint(model, foo[1, :] in SecondOrderCone())
[foo[1,11.0], foo[1,1.0], foo[1,100.0]] ∈ MathOptInterface.SecondOrderCone(3)
```

User could reasonably expect constraint function to be `[foo[1,1.0], foo[1,11.0], foo[1,100.0]]`.

[HIDDEN]

### Additional contract requirements

When a slice of a `SparseAxisArray` is converted to a vector, it must not silently yield values in an arbitrary order. The conversion may either preserve the order of the slice indices (as in the example) or issue a warning or error rather than return values in an arbitrary order.
