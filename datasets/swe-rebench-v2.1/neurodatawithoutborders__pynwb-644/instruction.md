Wrapping data with H5DataIO results in different interfaces for accessing the numerical data when round-tripping
## 1) Bug

When wrapping data in an H5DataIO object to support compression, the data interface when round-tripping is different. For example: when dealing with a TimeSeries, the TimeSeries for write has the actual data in TimeSeries.data.data, but the TimeSeries that is read in has the data in TimeSeries.data.

### Steps to Reproduce
```python
import os
import datetime
import numpy as np
from tempfile import gettempdir
from pynwb import NWBFile, NWBHDF5IO, TimeSeries
from pynwb.form.backends.hdf5.h5_utils import H5DataIO

times = np.arange(0, 10, 0.01)
data = np.sin(times)

ts_out = TimeSeries(
    name='some_data',
    source='numpy.sin',
    data=H5DataIO(data, compression=True, compression_opts=2),
    timestamps=times,
    unit='cm/s')

nwbfile_out = NWBFile(
    source='Data source',
    session_description='test',
    identifier='some_uuid',
    session_start_time=datetime.datetime.now(),
    file_create_date=datetime.datetime.now())

nwbfile_out.add_acquisition(ts_out)

filename = os.path.join(gettempdir(), "test.nwb")

with NWBHDF5IO(filename, mode='w') as io:
    io.write(nwbfile_out)

nwbfile_in = NWBHDF5IO(filename, mode='r').read()
ts_in = nwbfile_in.get_acquisition('some_data')
assert(np.allclose(ts_in.data, ts_out.data.data)) # works, but notice the required difference for accessing data
try:
    assert(np.allclose(ts_in.data, ts_out.data)) # fails with TypeError, as ts_out.data is an HDFDataIO object that doesn't support array behavior
finally:
os.remove(filename)
```
### Environment
Please describe your environment according to the following bullet points.
Linux, Python 3.6, pynwb 0.5.1

## Checklist

- [X] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [X] Have you included a brief and descriptive title?
- [X] Have you included a clear description of the problem you are trying to solve?
- [X] Have you included a minimal code snippet that reproduces the issue you are encountering?

### Additional contract requirements

- `pynwb.form.data_utils.DataIO` and its subclass `pynwb.form.backends.hdf5.h5_utils.H5DataIO` expose the attributes of the data they were constructed with: accessing an attribute on the wrapper returns the same attribute of the underlying data, and accessing an attribute the underlying data does not have raises `AttributeError`.
- A `DataIO` instance supports the iterator protocol: `iter(data_io)` yields the items of the underlying data, and `next(data_io)` returns the next item from the underlying data, raising `StopIteration` once the underlying data is exhausted.
- `pynwb.form.data_utils.DataChunk` exposes the attributes of the data it was constructed with: accessing an attribute on the chunk returns the same attribute of the underlying data, and accessing an attribute the underlying data does not have raises `AttributeError`.
