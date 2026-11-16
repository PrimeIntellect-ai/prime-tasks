[Bug]: Exponential1DSubMesh gives bad results
### PyBaMM Version

25.4.0

### Python Version

3.11.11

### Describe the bug

When running a simple DFN model and using the Exponential1DSubmesh, the results end up looking very strange.

<img width="1056" alt="Image" src="https://github.com/user-attachments/assets/75575633-a5e8-4f91-b44a-9321dc0365eb" />

I assume this is not just a plotting issue, though I am not sure.

### Steps to Reproduce

```
import pybamm

model = pybamm.lithium_ion.DFN()
parameter_values = model.default_parameter_values
parameter_values.process_model(model)

geometry = model.default_geometry
parameter_values.process_geometry(geometry)

submesh_types = model.default_submesh_types
submesh_types = {}
submesh_types.update({
    "negative electrode": pybamm.Exponential1DSubMesh,
    "negative particle": pybamm.Exponential1DSubMesh,
    "separator": pybamm.Exponential1DSubMesh,
    "positive electrode": pybamm.Exponential1DSubMesh,
    "positive particle": pybamm.Exponential1DSubMesh,
    "current collector": pybamm.SubMesh0D,
})
mesh = pybamm.Mesh(geometry, submesh_types, model.default_var_pts)
disc = pybamm.Discretisation(mesh, model.default_spatial_methods,check_model=True)

disc.process_model(model)

var_pts = {
    "x_n": 30,  # negative electrode
    "x_s": 20,  # separator
    "x_p": 30,  # positive electrode
    "r_n": 20,  # negative particle
    "r_p": 20,  # positive particle
}

sim = pybamm.Simulation(
    model=model,
    submesh_types=submesh_types,
    var_pts=var_pts,
    solver = pybamm.IDAKLUSolver()
)

sim.solve([0,3600])
```


### Relevant log output

```shell

```

### Additional contract requirements

- An `Exponential1DSubMesh` over an interval `[a, b]` must preserve both interval endpoints, including when `a` is nonzero, and its edges must be strictly increasing.
- The `side` setting controls the spacing bias: `left` means cell widths increase from left to right, `right` means they decrease from left to right, and `symmetric` means the mesh distribution is mirrored about the interval midpoint. These properties must hold for both odd and even requested point counts.
- With the mesh configured as in the reproduction, the DFN solve should not exhibit anomalous results caused by an incorrectly formed exponential mesh.
