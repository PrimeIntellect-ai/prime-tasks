Bug broadcasting an empty SparseAxisArray
@adow031 found this bug: https://github.com/odow/SDDP.jl/issues/497

```julia
julia> using JuMP

julia> model = Model()
A JuMP Model
Feasibility problem with:
Variables: 0
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.

julia> S = Any[]
Any[]

julia> @variable(model, x[S, S] >= 0, container = SparseAxisArray)
JuMP.Containers.SparseAxisArray{VariableRef, 2, Tuple{Any, Any}} with 0 entries

julia> lower_bound.(x)
ERROR: MethodError: no method matching JuMP.Containers.SparseAxisArray(::Dict{Any, Any})
Closest candidates are:
  JuMP.Containers.SparseAxisArray(::Dict{K, T}) where {T, N, K<:Tuple{Vararg{Any, N}}} at /Users/oscar/.julia/packages/JuMP/lnUbA/src/Containers/SparseAxisArray.jl:39
Stacktrace:
 [1] copy(bc::Base.Broadcast.Broadcasted{JuMP.Containers.BroadcastStyle{2, Tuple{Any, Any}}, Nothing, typeof(lower_bound), Tuple{JuMP.Containers.SparseAxisArray{VariableRef, 2, Tuple{Any, Any}}}})
   @ JuMP.Containers ~/.julia/packages/JuMP/lnUbA/src/Containers/SparseAxisArray.jl:186
 [2] materialize(bc::Base.Broadcast.Broadcasted{JuMP.Containers.BroadcastStyle{2, Tuple{Any, Any}}, Nothing, typeof(lower_bound), Tuple{JuMP.Containers.SparseAxisArray{VariableRef, 2, Tuple{Any, Any}}}})
   @ Base.Broadcast ./broadcast.jl:883
 [3] top-level scope
   @ REPL[60]:1
```
