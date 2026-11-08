[Bug]: Non-DCI H5DataIO does not passthrough `maxshape` property which crashes pynwb Timeseries
### What happened?

The pynwb documentation provides an example of passing a `H5DataIO` object as the `data` argument to the `TimeSeries` constructor. [docs here](https://pynwb.readthedocs.io/en/latest/tutorials/advanced_io/plot_iterative_write.html#alternative-approach-user-defined-dataset-write). However, this only works in the case where `timestamps=None` because, if timestamps is not None, then the `TimeSeries` initializer will check for the presence of `maxshape` and this fails because `H5DataIO` does not have `.maxshape`, it only has `.io_settings["maxshape"]`.

I raised this bug in pynwb here: https://github.com/NeurodataWithoutBorders/pynwb/issues/1929

Are there any unintended side-effects of adding a `maxshape` getter to `H5DataIO`?
Should this be fixed in pynwb? Maybe its `TimeSeries` `_check_time_series_dimension` can have a special case if the data object is H5DataIO.

For now I will monkey-patch H5DataIO to add a `maxshape` property.

### Steps to Reproduce

```python
import datetime
import numpy as np
from hdmf.backends.hdf5.h5_utils import H5DataIO
from pynwb import NWBHDF5IO, NWBFile, TimeSeries


def test_nwb_stream_timestamps():
    srate = 10.0
    data_shape = 20, 16, 2
    test_data = np.arange(np.prod(data_shape)).reshape(data_shape)

    dataio = H5DataIO(
        shape=(0,) + data_shape[1:],
        dtype=test_data.dtype,
        maxshape=(None,) + data_shape[1:],
        fillvalue=np.nan,
    )
    # Next line fails
    data_series = TimeSeries(
        name="some name",
        data=dataio,
        timestamps=np.arange(test_data.shape[0]),
        # rate=srate,  # Comment previous line and uncomment this to bypass error
        unit="n/a",
    )

    nwbfile = NWBFile(
        session_description="demonstrate streaming timestamps",
        identifier="abcd1234",
        session_start_time=datetime.datetime.now(datetime.timezone.utc),
    )
    nwbfile.add_acquisition(data_series)

    # Write the data to file
    file_path = Path(tempfile.gettempdir()) / "test_nwb_stream_timestamps.nwb"
    io = NWBHDF5IO(file_path, "w")
    io.write(nwbfile)

    dataio.dataset.resize(len(dataio.dataset) + len(data), axis=0)
    dataio.dataset[-len(data) :] = data
    timestampio.dataset.resize(len(timestampio.dataset) + len(timestamps), axis=0)
    timestampio.dataset[-len(timestamps) :] = timestamps

    io.close()
```


### Traceback

```pytb
>       data_series = TimeSeries(
            name="TODO: name from params",
            data=dataio,
            timestamps=timestampio,
            # rate=srate,
            unit="n/a",
        )

test_nwb.py:57:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
../../../.venv/lib/python3.9/site-packages/hdmf/utils.py:667: in func_call
    pargs = _check_args(args, kwargs)
../../../.venv/lib/python3.9/site-packages/hdmf/utils.py:639: in _check_args
    parsed = __parse_args(
../../../.venv/lib/python3.9/site-packages/hdmf/utils.py:351: in __parse_args
    valshape = get_data_shape(argval)
../../../.venv/lib/python3.9/site-packages/hdmf/utils.py:916: in get_data_shape
    if hasattr(data, 'maxshape'):
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <hdmf.backends.hdf5.h5_utils.H5DataIO object at 0x14755d190>
attr = 'maxshape'

    def __getattr__(self, attr):
        """Delegate attribute lookup to data object"""
        if attr == '__array_struct__' and not self.valid:
            # np.array() checks __array__ or __array_struct__ attribute dep. on numpy version
            raise InvalidDataIOError("Cannot convert data to array. Data is not valid.")
        if not self.valid:
>           raise InvalidDataIOError("Cannot get attribute '%s' of data. Data is not valid." % attr)
E           hdmf.data_utils.InvalidDataIOError: Cannot get attribute 'maxshape' of data. Data is not valid.

../../../.venv/lib/python3.9/site-packages/hdmf/data_utils.py:1104: InvalidDataIOError
```


### Operating System

macOS

### Python Executable

Python

### Python Version

3.9

### Package Versions

h5py==3.11.0
hdmf==3.14.1
hdmf_zarr==0.8.0
pynwb==2.8.0

### Additional contract requirements

- `H5DataIO` (module `hdmf.backends.hdf5.h5_utils`) exposes a public read-only property named `maxshape`.
- `H5DataIO.__init__` accepts an optional `maxshape` argument: a tuple whose elements are each an int or `None`, specifying the maximum size for each dimension. When supplied, the `maxshape` property returns that value.
- When `maxshape` is omitted, the property reports the wrapped data’s `maxshape` when available. Otherwise, it reports the `H5DataIO` shape when available, or the wrapped data’s shape when determinable.
