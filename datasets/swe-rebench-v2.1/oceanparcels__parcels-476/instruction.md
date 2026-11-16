Implement FieldSet.from_xarray_dataset()
Following the suggestion by @rabernat in #462, it would be good to implement a simple way to convert xarray `Datasets` to Parcels `FieldSets`.

### Additional contract requirements

Add a public classmethod `FieldSet.from_xarray_dataset(cls, ds, variables, dimensions, indices=None, mesh='spherical', allow_time_extrapolation=None, time_periodic=False, full_load=False, **kwargs)` in module `parcels.fieldset` (class `FieldSet`). It returns a new `FieldSet` whose primary fields `U` and `V` are built from the provided xarray `Dataset`:

- `variables` maps FieldSet variable names (e.g. 'U', 'V') to variable names inside the Dataset.
- `dimensions` maps logical dimensions ('lon', 'lat', 'depth', 'time') to the corresponding dimension names in the Dataset.
- `indices` is a dict of slice/list objects per dimension used to read a subset of the data; the resulting fields cover only the selected coordinates.
- `mesh` selects the coordinate type; 'flat' selects a flat mesh.
