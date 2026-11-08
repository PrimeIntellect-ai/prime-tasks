DynamicTable.to_dataframe cannot handle new DynamicTableRegion objects
## 1) Bug

Running `to_dataframe` on a `DynamicTable` that contains a `DynamicTableRegion` no longer works due to the changes to `DynamicTableRegion`. This is a common practice on the Units table, which uses `DynamicTableRegion` to store electrodes (as illustrated below) so I expect many users will be affected by this bug.

### Steps to Reproduce
```python
from pynwb import NWBFile

from datetime import datetime
from dateutil.tz import tzlocal

nwbfile = NWBFile('aa', 'aa', datetime(2017, 4, 15, 12, tzinfo=tzlocal()))

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

nwbfile.add_unit(id=1, electrodes=[1])
nwbfile.add_unit(id=2, electrodes=[1])

nwbfile.units.to_dataframe()
```

[HIDDEN]

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
