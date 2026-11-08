[Bug]: Export with link_data=False does not copy data
### What happened?

See description in https://github.com/NeurodataWithoutBorders/pynwb/issues/1683

### Steps to Reproduce

```shell
import h5py
import numpy as np

with h5py.File("pynwb_1683_data.h5", "w") as f:
    f.create_dataset(name="data", data=np.random.rand(5, 4))

from pynwb import NWBFile, NWBHDF5IO, validate, TimeSeries
import datetime


f = h5py.File("pynwb_1683_data.h5", "r")

nwbfile = NWBFile(
    session_description="session_description",
    identifier="identifier",
    session_start_time=datetime.datetime.now(datetime.timezone.utc),
)

ts = TimeSeries(
    name="test_ts",
    data=f["data"],
    unit="unit",
    rate=1.,
)
nwbfile.add_acquisition(ts)

filename = "pynwb_1683_test.nwb"

with NWBHDF5IO(filename, "w") as io:
    io.write(nwbfile)

with NWBHDF5IO(filename, "r") as io:
    read_nwbfile = io.read()
    print(read_nwbfile.acquisition["test_ts"].data.file)

export_filename = "pynwb_1683_export.nwb"

with NWBHDF5IO(filename, mode="r") as read_io:
    read_nwbfile = read_io.read()
    # read_nwbfile.generate_new_id()
    # nwbfile contains a TimeSeries where the TimeSeries data array is a link to an external dataset
    # in a different HDF5 file than self.read_path

    with NWBHDF5IO(export_filename, mode="w") as export_io:
        export_io.export(src_io=read_io, nwbfile=read_nwbfile, write_args={'link_data': False})

with NWBHDF5IO(export_filename, "r") as io:
    read_nwbfile = io.read()
    print(read_nwbfile.acquisition["test_ts"].data.file)
```


### Traceback

```shell
n/a
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

3.10

### Package Versions

dev branch of both PyNWB and HDMF

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

- `HDMFIO.export(src_io, container=None, write_args=dict(), clear_cache=False)` is available from `hdmf.backends.io`. When `write_args={'link_data': False}`, datasets linked from another HDF5 file must be copied into the export destination, so the exported data remains available without relying on the source file. This applies whether `container` is supplied or omitted. Setting `clear_cache=True` must produce the correct export even if the source I/O has already been read.
- `BuildManager.clear_cache()` is available from `hdmf.build.manager`. After it is called, later `build` or `construct` calls for the same inputs must return newly created objects rather than reuse previously returned ones.
