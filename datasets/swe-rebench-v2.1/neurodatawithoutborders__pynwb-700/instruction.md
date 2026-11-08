omitting tag in epochs causes error
## 1) Bug

```python
from pynwb import NWBFile
from datetime import datetime

nwbfile = NWBFile("a file with header data", "NB123A", datetime.now().astimezone())
nwbfile.create_epoch(start_time=0., stop_time=1.)
```

```python
/Users/bendichter/anaconda3/envs/dev_pynwb/lib/python3.6/site-packages/h5py/__init__.py:36: FutureWarning: Conversion of the second argument of issubdtype from `float` to `np.floating` is deprecated. In future, it will be treated as `np.float64 == np.dtype(float).type`.
  from ._conv import register_converters as _register_converters
Traceback (most recent call last):
  File "/Users/bendichter/dev/pynwb/test_electrodes.py", line 9, in <module>
    nwbfile.create_epoch(start_time=0., stop_time=1.)
  File "/Users/bendichter/dev/pynwb/src/pynwb/form/utils.py", line 375, in func_call
    return func(self, **parsed['args'])
  File "/Users/bendichter/dev/pynwb/src/pynwb/file.py", line 387, in create_epoch
    [HIDDEN]
TypeError: 'NoneType' object is not iterable
```

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
