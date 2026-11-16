[Bug]: `get_data_in_units` fails for ElectricalSeries with `channel_conversion`
### What happened?

https://github.com/NeurodataWithoutBorders/pynwb/pull/1745 added a method to get the data in the corect units which is something very nice that I always wanted.

One corner case that i think is not included is that the method will produce incorrect results with an `ElectricalSeries` object that has a channel conversion.

### Steps to Reproduce

This fails on the dev branch:


```python
from pynwb.testing.mock.ecephys import mock_ElectricalSeries

import numpy as np

data = np.asarray([[1, 1, 1, 1, 1], [1, 1, 1, 1, 1]])
conversion = 1.0
offset = 3.0
channel_conversion = np.asarray([2.0, 2.0])
electrical_series = mock_ElectricalSeries(
    data=data,
    conversion=conversion,
    offset=offset,
    channel_conversion=channel_conversion,
)

data_in_units = electrical_series.get_data_in_units()
expected_data =  data * conversion * channel_conversion[:, np.newaxis] + offset

np.testing.assert_almost_equal(data_in_units, expected_data)
```


### Traceback

```
AssertionError:
Arrays are not almost equal to 7 decimals

Mismatched elements: 10 [/](https://file+.vscode-resource.vscode-cdn.net/) 10 (100%)
Max absolute difference: 1.
Max relative difference: 0.2
 x: array([[4., 4., 4., 4., 4.],
       [4., 4., 4., 4., 4.]])
 y: array([[5., 5., 5., 5., 5.],
       [5., 5., 5., 5., 5.]])
```

### Operating System

Windows

### Python Executable

Conda

### Python Version

lower version (unsupported)

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
