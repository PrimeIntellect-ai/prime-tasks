Adding metadata to ParticleFile
For reproducibility, it would be good to add more metadata to a `ParticleFiles` object.

We should add at least be the version number of Parcels with which the file was generated, and probably also whether it was run in Scipy or JIT mode.

Furthermore, there should be a new method to add metadata to a `ParticleFile` object, so that users can for example store what type of diffusion constant they used

### Additional contract requirements

- The NetCDF file created by a `ParticleFile` must include an attribute named
  `parcels_version` whose value is the version string of the Parcels package that
  generated the file (equal to `parcels.__version__`).
- `ParticleFile.add_metadata(name, message)` must set the attribute `name` on the
  underlying netCDF4.Dataset to the value `message` and return `None`.
