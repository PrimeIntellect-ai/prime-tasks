thermal boundary condition in 1plus1D
when setting boundary conditions by tab in the 1plus1D models if there is a tab at either end, then the right boundary condition gets overridden by the "no tab" condition

### Additional contract requirements

- `pybamm.Discretisation(mesh, spatial_methods)` constructs a discretisation for the given mesh and spatial methods.
- `Discretisation.set_variable_slices(variables)` registers the variables to be sliced from the solution vector.
- `Discretisation.process_symbol(symbol)` returns a processed symbol and updates the `Discretisation.bcs` dictionary.
- For a `SubMesh1D` current collector, after processing, a boundary condition given for `"negative tab"` or `"positive tab"` is stored under the key `"left"` or `"right"` according to the tab locations stored in the mesh, preserving its value and type.
- A boundary condition given for `"no tab"` is stored under the side that has no tab: when a tab condition already occupies one side, the `"no tab"` condition is assigned to the opposite side; when both sides already have a tab condition, the `"no tab"` condition does not replace either of them.
