[Bug]: Reusing data across TimeSeries objects does not seem to work
### What happened?

PyNWB documentation & code seem to suggest that, similar to sharing timestamps between TimeSeries, we can also share data between TimeSeries. Passing a TimeSeries object to the data field of another TimeSeries does not error, but when reading the file back, the data fields don't appear to be linked, though I'd expect that they would be like the timestamps.

### Steps to Reproduce

```python
import numpy as np
from pynwb import NWBHDF5IO, NWBFile, TimeSeries
from datetime import datetime
from uuid import uuid4

nwbfile = NWBFile(
    session_description="not a real session",
    identifier=str(uuid4()),
    session_start_time=datetime.now(),
)

timeseries1 = TimeSeries(
    name="timeseries1",
    data=np.random.rand(40),
    unit="n/a",
    timestamps=(np.arange(40) * 1e-2),
)

timeseries2 = TimeSeries(
    name="timeseries2",
    data=timeseries1,
    unit="n/a",
    timestamps=timeseries1,
)

nwbfile.add_acquisition(timeseries1)
nwbfile.add_acquisition(timeseries2)

with NWBHDF5IO('temp.nwb', 'w') as io:
    io.write(nwbfile)

io = NWBHDF5IO('temp.nwb', 'r')
read_nwbfile = io.read()
print(nwbfile.acquisition['timeseries1'].timestamps == nwbfile.acquisition['timeseries2'].timestamps)
print(nwbfile.acquisition['timeseries1'].data == nwbfile.acquisition['timeseries2'].data)
print(nwbfile.acquisition['timeseries1'])
print(nwbfile.acquisition['timeseries2'])
```


### Traceback

```python
True
False
timeseries1 pynwb.base.TimeSeries at 0x140171917956080
Fields:
  comments: no comments
  conversion: 1.0
  data: <HDF5 dataset "data": shape (40,), type "<f8">
  description: no description
  interval: 1
  offset: 0.0
  resolution: -1.0
  timestamp_link: (
    timeseries2 <class 'pynwb.base.TimeSeries'>
  )
  timestamps: <HDF5 dataset "timestamps": shape (40,), type "<f8">
  timestamps_unit: seconds
  unit: n/a
timeseries2 pynwb.base.TimeSeries at 0x140171917958048
Fields:
  comments: no comments
  conversion: 1.0
  data: <HDF5 dataset "data": shape (40,), type "<f8">
  description: no description
  interval: 1
  offset: 0.0
  resolution: -1.0
  timestamps: timeseries1 pynwb.base.TimeSeries at 0x140171917956080
Fields:
  comments: no comments
  conversion: 1.0
  data: <HDF5 dataset "data": shape (40,), type "<f8">
  description: no description
  interval: 1
  offset: 0.0
  resolution: -1.0
  timestamp_link: (
    timeseries2 <class 'pynwb.base.TimeSeries'>
  )
  timestamps: <HDF5 dataset "timestamps": shape (40,), type "<f8">
  timestamps_unit: seconds
  unit: n/a

  timestamps_unit: seconds
  unit: n/a
```


### Operating System

Linux

### Python Executable

Python

### Python Version

3.10

### Package Versions

(run on DANDI hub)
[issue_environment.txt](https://github.com/NeurodataWithoutBorders/pynwb/files/12420538/issue_environment.txt)


### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
