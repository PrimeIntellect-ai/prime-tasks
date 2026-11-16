[Bug]: SpatialSeries.reference_frame should be optional
### What happened?

The [spec for `SpatialSeries`](https://github.com/NeurodataWithoutBorders/nwb-schema/blob/dev/core/nwb.behavior.yaml#L59-L62) says that the "reference_frame" dataset is optional. However, it is a required argument in pynwb to the `SpatialSeries` constructor.

This is blocking a user from validating their NWB files for upload onto DANDI after creating them using MatNWB.

### Steps to Reproduce

```python
n/a
```


### Traceback

_No response_

### Operating System

Windows

### Python Executable

Conda

### Python Version

3.11

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?

### Additional contract requirements

- `SpatialSeries` is a public class in the `pynwb.behavior` module.
- The `SpatialSeries` constructor accepts `reference_frame` as an optional keyword argument that defaults to `None`. When `reference_frame` is omitted, the constructed object's `reference_frame` attribute is `None`.
