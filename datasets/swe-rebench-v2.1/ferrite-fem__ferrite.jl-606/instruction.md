Extract boundary entities
Following the discussion in #565 it is helpful to add utilities to extract boundary entities (faces, edges, ...). Boundary faces can be identified as a function of the grid and a topology. So maybe something like `addboundaryfaceset!(grid, topology, "bottom" x -> norm(x[3]) ≈ 0.0);` makes sense.

### Additional contract requirements

The `Ferrite` module must provide the following public functions. `addboundaryfaceset!`, `addboundaryedgeset!` and `addboundaryvertexset!` must be exported; the remaining functions must be accessible as `Ferrite.<name>`:

- `addboundaryfaceset!(grid, topology, name::String, f::Function; all::Bool=true)`: adds a boundary face set under the key `name` to `grid` and returns the same (mutated) `grid`. `f` receives a node coordinate vector and returns `Bool`. With `all=true` (the default) `f` must hold for every node of a face for that face to be included; with `all=false` it suffices that `f` holds for one node. The result is stored as `grid.facesets[name]::Set{FaceIndex}` and contains every face instance that shares the vertices of a matching boundary face.
- `addboundaryedgeset!(grid, topology, name::String, f::Function; all::Bool=true)`: the edge analogue of `addboundaryfaceset!`, storing `grid.edgesets[name]::Set{EdgeIndex}` and returning the same (mutated) `grid`.
- `addboundaryvertexset!(grid, topology, name::String, f::Function; all::Bool=true)`: the vertex analogue of `addboundaryfaceset!`, storing `grid.vertexsets[name]::Set{VertexIndex}` and returning the same (mutated) `grid`.
- `getfaceedges(grid, face::FaceIndex) -> Set{EdgeIndex}`: the edges of the given face.
- `getfacevertices(grid, face::FaceIndex) -> Set{VertexIndex}`: the vertices of the given face.
- `getedgevertices(grid, edge::EdgeIndex) -> Set{VertexIndex}`: the two vertices of the given edge.
- `filterfaces(grid, faces::Set{FaceIndex}, f::Function; all::Bool=true) -> Set{FaceIndex}`: the subset of `faces` satisfying `f`, using the same `all` semantics as above.
- `filteredges(grid, edges::Set{EdgeIndex}, f::Function; all::Bool=true) -> Set{EdgeIndex}`: the subset of `edges` satisfying `f`, using the same `all` semantics as above.
- `filtervertices(grid, vertices::Set{VertexIndex}, f::Function; all::Bool=true) -> Set{VertexIndex}`: the subset of `vertices` whose coordinate satisfies `f`.
- `getfaceinstances(grid, topology, face::FaceIndex) -> Set{FaceIndex}`: all faces sharing exactly the input face's vertex set, including the input face.
