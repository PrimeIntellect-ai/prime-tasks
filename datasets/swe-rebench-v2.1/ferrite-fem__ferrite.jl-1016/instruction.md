Dirichlet does not work with concretely typed functions
Originally found by @firimo

https://github.com/Ferrite-FEM/Ferrite.jl/blob/622878270bc8156bb70a4658ce01ef6dde1e4aa3/src/Dofs/ConstraintHandler.jl#L409 calls the wrong function if the time-dependent function has a only a dispatch with concrete types.

```julia-repl
julia> f(::Real,::Real) = 1.0
f (generic function with 1 method)

julia> hasmethod(f, Tuple{Any,Any})
false

julia> hasmethod(f, Tuple{<:Any,<:Any})
false
```

see also

```julia-repl
julia> fun(::Real,::Real) = 3.0
fun (generic function with 1 method)

julia> fun(::Real) = 4.0
fun (generic function with 2 methods)

julia> fun(::Vec) = 2.0
fun (generic function with 3 methods)

julia> fun(::Vec, ::Real) = 1.0
fun (generic function with 4 methods)

julia> ch = ConstraintHandler(dh)
ConstraintHandler:
  Not closed!

julia> add!(ch, Dirichlet(:u, getfacetset(grid, "left"), fun))
ConstraintHandler:
  Not closed!

julia> close!(ch)
ConstraintHandler:
  BCs:
    Field: u, Components: [1]

julia> apply!(u, ch)
8-element Vector{Float64}:
 2.0
 0.0
 2.0
 2.0
 2.0
 0.0
 0.0
 0.0
```

or

```julia-repl
julia> fun2(::Vec, ::Real) = 1.0
fun2 (generic function with 1 method)

julia> ch = ConstraintHandler(dh)
ConstraintHandler:
  Not closed!

julia> add!(ch, Dirichlet(:u, getfacetset(grid, "left"), fun2))
ConstraintHandler:
  Not closed!

julia> close!(ch)
ERROR: MethodError: no method matching fun2(::Vec{3, Float64})

Closest candidates are:
  fun2(::Vec, ::Real)
   @ Main REPL[89]:1

Stacktrace:
 [1] (::Ferrite.var"#355#356"{Dirichlet})(x::Vec{3, Float64}, ::Float64)
   @ Ferrite ~/.julia/packages/Ferrite/Fgzgk/src/Dofs/ConstraintHandler.jl:402
 [2] _update!(inhomogeneities::Vector{…}, f::Ferrite.var"#355#356"{…}, boundary_entities::OrderedCollections.OrderedSet{…}, field::Symbol, local_facet_dofs::Vector{…}, local_facet_dofs_offset::Vector{…}, components::Vector{…}, dh::DofHandler{…}, boundaryvalues::Ferrite.BCValues{…}, dofmapping::Dict{…}, dofcoefficients::Vector{…}, time::Float64)
   @ Ferrite ~/.julia/packages/Ferrite/Fgzgk/src/Dofs/ConstraintHandler.jl:446
 [3] update!(ch::ConstraintHandler{DofHandler{3, Grid{3, Tetrahedron, Float64}}, Float64}, time::Float64)
   @ Ferrite ~/.julia/packages/Ferrite/Fgzgk/src/Dofs/ConstraintHandler.jl:404
 [4] update!
   @ ~/.julia/packages/Ferrite/Fgzgk/src/Dofs/ConstraintHandler.jl:397 [inlined]
 [5] close!(ch::ConstraintHandler{DofHandler{3, Grid{3, Tetrahedron, Float64}}, Float64})
   @ Ferrite ~/.julia/packages/Ferrite/Fgzgk/src/Dofs/ConstraintHandler.jl:251
 [6] top-level scope
   @ REPL[92]:1
Some type information was truncated. Use `show(err)` to see complete types.
```
