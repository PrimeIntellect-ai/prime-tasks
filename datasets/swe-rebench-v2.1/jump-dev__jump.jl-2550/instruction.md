[Useability] `@constraint` and `@variable`: cannot use an iterator
I am working with graphs, basically generating one variable per edge and then adding constraints. However, when I cannot use the usual syntax `@variable(m, x[e in Iterators.filter(k -> true, edges(g))])`, due to `Iterators.filter(k -> true, edges(g))` returning an iterator whose size is unknown a priori:

```
ERROR: MethodError: no method matching length(::Base.Iterators.Filter{getfield(Main, Symbol("##1670#1674")),LightGraphs.SimpleGraphs.SimpleEdgeIter{SimpleDiGraph{Int64}}})
Closest candidates are:
  length(::Core.SimpleVector) at essentials.jl:582
  length(::Base.MethodList) at reflection.jl:732
  length(::Core.MethodTable) at reflection.jl:806
  ...
```

An minimum "working" example:

```julia
using JuMP, LightGraphs
g = PathGraph(3)
m = Model()
@variable(m, x[e in Iterators.filter(k -> true, edges(g))] = 0)
```

For anyone else facing this issue, the solution is simple: put a `collect` to transform the iterator into an array.

[HIDDEN]

### Additional contract requirements

JuMP’s `@variable` and `@constraint` container syntax must accept finite iterators with unknown size by materializing them so the container can be formed. JuMP must reject an iterator known to be infinite rather than try to form a container from it.
