Units['electrode_group'] does not accept ElectrodeGroup objects
## 1) Bug

### Steps to Reproduce
```python
from pynwb import NWBFile
from datetime import datetime

nwbfile = NWBFile('aa','aa', datetime.now().astimezone())

device = nwbfile.create_device(name='trodes_rig123')
electrode_name = 'tetrode1'
description = "an example tetrode"
location = "somewhere in the hippocampus"
electrode_group = nwbfile.create_electrode_group(electrode_name,
                                                 description=description,
                                                 location=location,
                                                 device=device)
for idx in [1, 2, 3, 4]:
    nwbfile.add_electrode(idx,
                          x=1.0, y=2.0, z=3.0,
                          imp=float(-idx),
                          location='CA1', filtering='none',
                          group=electrode_group)

nwbfile.add_unit(id=1, electrodes=[1], electrode_group=electrode_group)
nwbfile.add_unit(id=2, electrodes=[1], electrode_group=electrode_group)
```

```python
Traceback (most recent call last):
  File "/Users/bendichter/Library/Preferences/PyCharmCE2018.3/scratches/scratch_1.py", line 21, in <module>
    nwbfile.add_unit(id=1, electrodes=[1], electrode_group=electrode_group)
  File "/Users/bendichter/dev/pynwb/src/pynwb/form/utils.py", line 379, in func_call
    raise_from(ExceptionType(msg), None)
  File "<string>", line 3, in raise_from
TypeError: incorrect type for 'electrode_group' (got 'ElectrodeGroup', expected 'ndarray, list, tuple, Dataset, AbstractDataChunkIterator or FORMDataset')
```

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?

### Additional contract requirements

- `Units.add_unit` and `NWBFile.add_unit` return `None`.
