Tests failing on Julia v1.11
The errors are happening in CI and I can also reproduce them locally.

```
CSets: Error During Test at /home/runner/work/Catlab.jl/Catlab.jl/test/categorical_algebra/CSets.jl:350
  Test threw exception
  Expression: ob(terminal(VELabeledGraph; loose = true)) == cycle_graph(VELabeledGraph{Tuple{}}, 1; E = (; elabel = [()]), V = (; vlabel = [()]))
  MethodError: no method matching limit(::Type{Tuple{Main.TestCategoricalAlgebra.TestCSets.VELabeledGraph, Catlab.CategoricalAlgebra.CSets.LooseACSetTransformation}}, ::Catlab.CategoricalAlgebra.FreeDiagrams.EmptyDiagram{Main.TestCategoricalAlgebra.TestCSets.VELabeledGraph, Catlab.CategoricalAlgebra.CSets.LooseACSetTransformation, StaticArraysCore.SVector{0, Main.TestCategoricalAlgebra.TestCSets.VELabeledGraph}})
  The function `limit` exists, but no method is defined for this combination of argument types.

  Closest candidates are:
    limit(::Type{Tuple{ACS, Hom}}, ::Any; product_attrs) where {S, Ts, ACS<:(ACSets.DenseACSets.StructACSet{S, Ts}), Hom<:Catlab.CategoricalAlgebra.CSets.LooseACSetTransformation}
     @ Catlab ~/work/Catlab.jl/Catlab.jl/src/categorical_algebra/CSets.jl:837
    limit(::Any, ::Nothing; kw...)
     @ Catlab ~/work/Catlab.jl/Catlab.jl/src/categorical_algebra/Limits.jl:133
    limit(::Type{<:Tuple{ACS, Catlab.CategoricalAlgebra.CSets.CSetTransformation}}, ::Any; attrfun) where {S, ACS<:(ACSets.DenseACSets.StructACSet{S})}
     @ Catlab ~/work/Catlab.jl/Catlab.jl/src/categorical_algebra/CSets.jl:814
    ...
```

Also:

```text
 CSets: Test Failed at /home/runner/work/Catlab.jl/Catlab.jl/test/categorical_algebra/HomSearch.jl:157
  Expression: homomorphism(K₆, K₆, any = true) != homomorphism(K₆, K₆; any = true, random = true)
   Evaluated: ACSetTransformation((V = FinFunction([1, 2, 3, 4, 5, 6], 6, 6), E = FinFunction([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30], 30, 30)), Catlab.Graphs.BasicGraphs.SymmetricGraph {V:6, E:30}, Catlab.Graphs.BasicGraphs.SymmetricGraph {V:6, E:30}) != ACSetTransformation((V = FinFunction([1, 2, 3, 4, 5, 6], 6, 6), E = FinFunction([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30], 30, 30)), Catlab.Graphs.BasicGraphs.SymmetricGraph {V:6, E:30}, Catlab.Graphs.BasicGraphs.SymmetricGraph {V:6, E:30})
```

### Additional contract requirements

- Passing `random = true` to a homomorphism search must return the same collection of homomorphisms as the non-random search, up to order. A randomized search may return the same single homomorphism as the deterministic search; returning a different one is not required.
