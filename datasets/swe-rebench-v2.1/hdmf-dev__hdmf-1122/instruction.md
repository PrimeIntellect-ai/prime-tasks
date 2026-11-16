[Bug]: Resolving spec inheritance fails when attribute has same name as existing attr on another object
### What happened?

From https://github.com/catalystneuro/ndx-microscopy/pull/11#discussion_r1622645107

The relevant spec:
```yaml
  - neurodata_type_def: ImagingSpace
    neurodata_type_inc: LabMetaData  # Would prefer basic NWBContainer
    doc: Metadata about the region of physical space that imaging data was recorded from.
    datasets:
    - name: origin_coordinates
      dtype: float64
      dims:
        - - x, y, z
      shape:
        - - 3
      doc: Physical location in stereotactic coordinates for the first element of the grid.
        See reference_frame to determine what the coordinates are relative to (e.g., bregma).
      quantity: '?'
      attributes:
        - name: unit
          dtype: text
          default_value: micrometers
          doc: Measurement units for origin coordinates. The default value is 'micrometers'.

  - neurodata_type_def: PlanarImagingSpace
    neurodata_type_inc: ImagingSpace
    doc: Metadata about the 2-dimensional slice of physical space that imaging data was recorded from.
    datasets:
    - name: grid_spacing
      dtype: float64
      dims:
        - - x, y
      shape:
        - - 2
      doc: Amount of space between pixels in the specified unit.
        Specify 'z' only when imaging volume is a regular grid; otherwise only specify 'x' and 'y'.
        See origin_coordinates to determine where the grid begins.
      quantity: '?'
      attributes:
        - name: unit
          dtype: text
          default_value: micrometers
          doc: Measurement units for grid spacing. The default value is 'micrometers'.
```

After doing some digging, I found that because `ImagingSpec.origin_coordinates` has an attribute `unit` and `PlanarImagingSpace.grid_spacing` also has an attribute `unit`, that when determining whether `PlanarImagingSpace.grid_spacing.unit` is inherited or not, HDMF says yes it is inherited because when `ImagingSpec.origin_coordinates` is inherited and it has an attribute with the same name, `unit`. That is not correct.

I have a fix.

### Steps to Reproduce

```python
Install ndx-microscopy linked above. Uncomment `unit` attribute spec on the `PlanarImagingSpace` spec. Instantiate a `PlanarImagingSpace` with `grid_spacing__unit="unit"`
```


### Traceback

_No response_

### Operating System

macOS

### Python Executable

Conda

### Python Version

3.12

### Package Versions

_No response_

### Additional contract requirements

- `BaseStorageSpec.is_inherited_spec(spec)` and `BaseStorageSpec.is_overridden_spec(spec)` in the `hdmf.spec.spec` module take a `Spec` object (not a string name) and return a `bool`. Passing a string name raises a `TypeError`.
- `GroupSpec.is_inherited_spec(spec)` and `GroupSpec.is_overridden_spec(spec)` in the `hdmf.spec.spec` module likewise take a `Spec` object (not a string name) and return a `bool`. Passing a string name raises a `TypeError`.
- These methods return `False` when the given spec cannot be found in the storage spec. `is_overridden_spec` also returns `False` when the spec cannot be overridden (for example, an unnamed link spec).
- `GroupSpec.is_inherited_spec` and `GroupSpec.is_overridden_spec` cover group-level components (links, sub-groups, datasets, data types, target types) and attributes nested inside inherited datasets or groups.
