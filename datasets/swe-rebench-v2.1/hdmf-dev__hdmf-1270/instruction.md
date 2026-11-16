[Bug]: get_data_shape on list of Data objects is incorrect
### What happened?

`get_data_shape` is used in many places, including shape validation and getting dimension labels. In NWB, an `Image` neurodata type is a descendent of `Data`, i.e., a dataset. `ImageReferences` has a field that stores a 1-D list/array of `Image` objects. However, when validating the shape of input to that field in `ImageReferences`, `get_data_shape` recurses into the `Image` data to get the shape of the images. As a result, a 1-D list of references to `Image` objects, which on disk has shape `(N, )`, will be reported by `get_data_shape` as having shape `(N, W, H)`. where (W, H) is the shape of the first image. The schema says the field should have shape `(N, )`.

Secondly, writing valid `ImageReferences` produces a warning on write:
  /Users/rly/Documents/NWB/hdmf/src/hdmf/build/objectmapper.py:874: IncorrectDatasetShapeBuildWarning: Shape of data does not match shape in spec 'ImageReferences'
    warnings.warn(msg, IncorrectDatasetShapeBuildWarning)

This occurs when getting dimension labels.

`get_data_shape` on a list/array of Data objects (a dataset of references) should return the shape of the list/array and not recurse deeper.

### Steps to Reproduce

```python
get_data_shape([Data(name="a", data=[1, 2]), Data(name="b", data=[3, 4])])
```

### Traceback

```pytb

```

### Operating System

macOS

### Python Version

3.13

### Package Versions

_No response_
