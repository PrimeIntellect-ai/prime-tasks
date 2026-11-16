[Bug]: Warning raised in RoiResponseSeries when data second dimension correctly matches length of rois
### What happened?

This warning is raised from RoiResponseSeries: `The second dimension of data does not match the length of rois. Your data may be transposed.` when data has more than one dimension, e.g., `np.ones((6, 2))`, and rois has more than one element, e.g., `[0, 1]`. This is correct and should not result in a warning.

All of the tests currently test RoiResponseSeries where data has one dimension, e.g., `[1, 2, 3]` and rois has just one element, e.g., `[1]`. This does not generate the warning.


### Steps to Reproduce

```python
ps = create_plane_segmentation()
rt_region = ps.create_roi_table_region(description='the first two ROIs', region=[0, 1])
RoiResponseSeries(
    name="test_ts1",
    data=np.ones((6, 2)),
    rois=rt_region,
    rate=30000.,
    unit="n.a.",
)
```


### Traceback

_No response_

### Operating System

Windows

### Python Executable

Python

### Python Version

3.9

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
