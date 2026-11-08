Error when adding Dirichlet on nodes for MixedDofHandler
Error happens here: https://github.com/Ferrite-FEM/Ferrite.jl/blob/9de9677fb3fb0e78601271a39c123b04ee2636f6/src/Dofs/ConstraintHandler.jl#L911 [HIDDEN]

Repro:
```
grid = generate_grid(Line, (2,))
dh = MixedDofHandler(grid)
push!(dh, :u, 2)
close!(dh)
ch = ConstraintHandler(dh)
add!(ch, Dirichlet(:u, Set(1), x -> 0))
```

### Additional contract requirements

- Adding a node-based Dirichlet constraint with a `Set{Int}` of node IDs to a `ConstraintHandler` for a `MixedDofHandler` must succeed and prescribe the constrained field’s degrees of freedom at those nodes.
- Fields of a `MixedDofHandler` are grouped into `FieldHandler` objects and registered with `add!(dh, fh)`, as in the repository's current API; this is how the mixed-grid examples in this request are set up.
