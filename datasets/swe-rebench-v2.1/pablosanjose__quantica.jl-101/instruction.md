Mixing non-scalar parameters and Bloch phases
There is a serious design problem that has been inadvertently introduced in #52. By combining parameters and Bloch phases into a single `(params..., ϕs...)` tuple, to be used in `bloch`, `bandstructure`, `mesh` etc.., I did not consider a use case where `params` are not `Number`s (`ϕs` are always `Real`s).

Indeed, it is not unlikely that a `ParametricHamiltonian` has parameters that are vectors, matrices, or more complicated types. In such case,  `(params..., ϕs...)` is not an `NTuple{N,Number}`, and hence cannot be converted to a `SVector` of concrete eltype (which is what we internally use for Bloch phases) if there are both `params` and `ϕs`.

The problem runs deep, because when building bandstructures, we need to build a mesh where each vertex is `SVector(params..., ϕs...)`. We further need a `norm` to be defined on these vertices, because we use distances in mesh space for co-diagonalization.

A possible solution is to only allow non-numeric `params` in the case where there are no `ϕs` (i.e. in zero-dimensional `ParametricHamiltonian`s). A less drastic approach is to allow them for creating `ParametricHamiltonian`, but not when calling `bloch` or `buildmesh`. Even with such restriction, a notion of distance is needed for non-numeric types, which probably cannot be defined in general.

[HIDDEN] This entails a thorough revision of recent PRs that enabled bandstructures as a function of parameters (i.e. a serious amount of work).

### Additional contract requirements

Mesh vertices used for mesh-backed operations have numeric scalar coordinates. A marching mesh request with non-numeric range endpoints must be rejected with an `ArgumentError`. Non-Number parameters such as vectors are supported alongside nonzero Bloch phases in a mesh-backed bandstructure when they remain parameter values separate from the mesh coordinates: the mesh coordinates remain numeric, and a lift may map them to the parameter values and Bloch phases. Such an operation must complete and produce a bandstructure rather than failing during mesh construction, conversion, or distance calculation.
