Topology Bug
```julia
> grid = generate_grid(Hexahedron, (2, 1, 1))
> topo = ExclusiveTopology(grid)
> getneighborhood(topo, grid, FaceIndex(2,6), true)

ERROR: BoundsError
Stacktrace:
 [1] getindex(A::SparseArrays.SparseMatrixCSC{Ferrite.EntityNeighborhood, Int64}, i0::Int64, i1::Int64)
   @ SparseArrays ~/Tools/julia-1.7.2/share/julia/stdlib/v1.7/SparseArrays/src/sparsematrix.jl:2159
 [2] getneighborhood(top::ExclusiveTopology, grid::Grid{3, Hexahedron, Float64}, faceidx::FaceIndex, include_self::Bool)
   @ Ferrite ~/.julia/packages/Ferrite/X5BVa/src/Grid/grid.jl:0
 [3] top-level scope
   @ REPL[15]:1
```

and

```julia
julia> grid = generate_grid(QuadraticQuadrilateral, (3, 1));

julia> topo = ExclusiveTopology(grid)
ExclusiveTopology(Dict(5 => [2, 3], 15 => [1], 7 => [3], 21 => [3], 17 => [1, 2], 3 => [1, 2], 1 => [1], 19 => [2, 3]), Ferrite.EntityNeighborhood{CellIndex}[Ferrite.EntityNeighborhood{CellIndex}(CellIndex[CellIndex(2)]), Ferrite.EntityNeighborhood{CellIndex}(CellIndex[CellIndex(1), CellIndex(3)]), Ferrite.EntityNeighborhood{CellIndex}(CellIndex[CellIndex(2)])], sparse(Int64[], Int64[], Ferrite.EntityNeighborhood[], 0, 0), sparse(Int64[], Int64[], Ferrite.EntityNeighborhood[], 0, 0), sparse(Int64[], Int64[], Ferrite.EntityNeighborhood[], 0, 0), Dict{Int64, Ferrite.EntityNeighborhood{VertexIndex}}(5 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((2, 1)), VertexIndex((2, 3)), VertexIndex((3, 2)), VertexIndex((3, 4))]), 15 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((1, 1)), VertexIndex((1, 3))]), 7 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((3, 1)), VertexIndex((3, 3))]), 21 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((3, 2)), VertexIndex((3, 4))]), 17 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((1, 2)), VertexIndex((1, 4)), VertexIndex((2, 1)), VertexIndex((2, 3))]), 3 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((1, 1)), VertexIndex((1, 3)), VertexIndex((2, 2)), VertexIndex((2, 4))]), 1 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((1, 2)), VertexIndex((1, 4))]), 19 => Ferrite.EntityNeighborhood{VertexIndex}(VertexIndex[VertexIndex((2, 2)), VertexIndex((2, 4)), VertexIndex((3, 1)), VertexIndex((3, 3))])), FaceIndex[FaceIndex((1, 1)), FaceIndex((1, 2)), FaceIndex((1, 3)), FaceIndex((1, 4)), FaceIndex((2, 1)), FaceIndex((2, 2)), FaceIndex((2, 3)), FaceIndex((3, 1)), FaceIndex((3, 2)), FaceIndex((3, 3))])

julia> topo.
cell_neighbor          edge_neighbor           face_neighbor           face_skeleton           vertex_neighbor         vertex_to_cell          vertex_vertex_neighbor
julia> topo.face_neighbor
0×0 SparseArrays.SparseMatrixCSC{Ferrite.EntityNeighborhood, Int64} with 0 stored entries
```

### Additional contract requirements

The following functions must be available in the `Ferrite` module and must accept any `AbstractGrid` (not only the concrete `Grid`):

- `getneighborhood(top::ExclusiveTopology, grid::AbstractGrid, cellidx::CellIndex, include_self::Bool=false) -> Vector{Int}`: returns the directly adjacent cells of `cellidx`. When `include_self` is `true`, the result also contains the requested cell identifier.
- `getneighborhood(top::ExclusiveTopology, grid::AbstractGrid, faceidx::FaceIndex, include_self::Bool=false) -> Vector{FaceIndex}`: returns the neighboring faces that share the same geometric face. When `include_self` is `true`, the result also contains `faceidx`.
- `getneighborhood(top::ExclusiveTopology, grid::AbstractGrid, vertexidx::VertexIndex, include_self::Bool=false) -> Vector{VertexIndex}`: returns the vertices directly connected to `vertexidx` via faces/edges. When `include_self` is `true`, the result also contains the local representations of the same global vertex in all incident cells.
- `getneighborhood(top::ExclusiveTopology, grid::AbstractGrid, edgeidx::EdgeIndex, include_self::Bool=false) -> Vector{EdgeIndex}`: returns the edges sharing the same geometric edge. When `include_self` is `true`, the result also contains the local edge representations of the same geometric edge in all incident cells plus `edgeidx`.
- `toglobal(grid::AbstractGrid, vertexidx::VertexIndex) -> Int`: returns the unique global vertex identifier of the local vertex.
- `toglobal(grid::AbstractGrid, vertexidx::Vector{VertexIndex}) -> Vector{Int}`: returns the deduplicated global vertex identifiers of the supplied local vertices.

For `hexgrid = generate_grid(Hexahedron, (2, 2, 1))`, `getneighborhood(topology, hexgrid, EdgeIndex(1, 11), true)` returns `[EdgeIndex(4, 9), EdgeIndex(2, 12), EdgeIndex(3, 10), EdgeIndex(1, 11)]`, and `getneighborhood(topology, hexgrid, EdgeIndex(2, 12), true)` returns `[EdgeIndex(3, 10), EdgeIndex(1, 11), EdgeIndex(4, 9), EdgeIndex(2, 12)]`.

For `quadgrid = generate_grid(Quadrilateral, (3, 3))`, `getneighborhood(topology, quadgrid, VertexIndex(1,1))` returns `[VertexIndex(1,2), VertexIndex(1,4)]`; `getneighborhood(topology, quadgrid, VertexIndex(2,1))` returns `[VertexIndex(1,1), VertexIndex(1,3), VertexIndex(2,2), VertexIndex(2,4)]`; and `getneighborhood(topology, quadgrid, VertexIndex(5,4))` returns `[VertexIndex(4,2), VertexIndex(4,4), VertexIndex(5,1), VertexIndex(5,3), VertexIndex(7,1), VertexIndex(7,3), VertexIndex(8,2), VertexIndex(8,4)]`. With `include_self=true`, those calls return `[VertexIndex(1,2), VertexIndex(1,4), VertexIndex(1,1)]`, `[VertexIndex(1,1), VertexIndex(1,3), VertexIndex(2,2), VertexIndex(2,4), VertexIndex(1,2), VertexIndex(2,1)]`, and `[VertexIndex(4,2), VertexIndex(4,4), VertexIndex(5,1), VertexIndex(5,3), VertexIndex(7,1), VertexIndex(7,3), VertexIndex(8,2), VertexIndex(8,4), VertexIndex(4,3), VertexIndex(5,4), VertexIndex(7,2), VertexIndex(8,1)]`, respectively. The corresponding `toglobal` calls on the neighborhoods without self return `[2,5]`, `[1,6,3]`, and `[6,9,11,14]`, respectively.
