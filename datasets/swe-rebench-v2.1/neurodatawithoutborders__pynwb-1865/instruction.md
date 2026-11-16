[Bug]: Exception reading linked NWBFile with `TimeSeriesReference` in `NWBFile.trials`
### What happened?

Dataset linking is breaking after adding a TimeSeriesReference to the NWB `trials` `TimeIntervals` table.
The result is a failure to read the NWBFile.
It seems that the constructor in `pynwb.io.epochs.TimeIntervalsMap` is getting a `LinkBuilder` but isn't aware of how to handle it.

Without knowing any details, it appears that [HIDDEN]
https://github.com/NeurodataWithoutBorders/pynwb/blob/65b2a7d0ea642132a7a5fcb5a5199b675f092e0b/src/pynwb/io/epoch.py#L16-L18

Seems pretty similar to #1223 but I'm reporting a new bug since this involves `pynwb.io.epochs` rather than `pynwb.io.misc`.

### Steps to Reproduce

```python
from datetime import datetime
from uuid import uuid4
import os
import numpy as np
from dateutil.tz import tzlocal

from pynwb import NWBFile, TimeSeries, NWBHDF5IO

# create the NWBFile
new_nwb = NWBFile(
    session_description="my first synthetic recording",  # required
    identifier=str(uuid4()),  # required
    session_start_time=datetime(2017, 4, 3, 11, tzinfo=tzlocal()),  # required
    experimenter="Baggins, Bilbo",  # optional
    lab="Bag End Laboratory",  # optional
    institution="University of Middle Earth at the Shire",  # optional
    experiment_description="I went on an adventure with thirteen dwarves to reclaim vast treasures.",  # optional
    session_id="LONELYMTN",  # optional
)
# create some example TimeSeries
test_ts = TimeSeries(
    name="series1",
    data=np.arange(1000),
    unit="m",
    timestamps=np.linspace(0.5, 601, 1000),
)
rate_ts = TimeSeries(
    name="series2", data=np.arange(600), unit="V", starting_time=0.0, rate=1.0
)
# Add the TimeSeries to the file
new_nwb.add_acquisition(test_ts)
new_nwb.add_acquisition(rate_ts)

new_nwb.add_trial(start_time=1.0, stop_time=2.0, timeseries=[test_ts])
new_nwb.add_trial(start_time=10.0, stop_time=11.0, timeseries=[test_ts, rate_ts])
new_nwb.add_trial(start_time=30.0, stop_time=31.0, timeseries=[test_ts, rate_ts])

with NWBHDF5IO('test_a.h5', 'w') as io:
    io.write(new_nwb)

with NWBHDF5IO('test_a.h5', 'r') as base_io:
    nwb_add = base_io.read().copy()
    new_nwb.add_acquisition(TimeSeries(name='series3', unit='V', data=np.arange(300), rate=0.5))
    with NWBHDF5IO('test_b.h5', 'w', manager=base_io.manager) as out_io:
        out_io.write(nwb_add)

try:
    with NWBHDF5IO('test_a.h5', 'r') as io:
        nwb = io.read()
        print(len(nwb.trials))
    with NWBHDF5IO('test_b.h5', 'r') as io:
        nwb = io.read()
        print(len(nwb.trials))
finally:
    os.unlink('test_a.h5')
    os.unlink('test_b.h5')
```


### Traceback

```python
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
Cell In[1], line 52
     50         print(len(nwb.trials))
     51     with NWBHDF5IO('test_b.h5', 'r') as io:
---> 52         nwb = io.read()
     53         print(len(nwb.trials))
     54 finally:

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/pynwb/__init__.py:304, in NWBHDF5IO.read(self, **kwargs)
    301         raise TypeError("NWB version %s not supported. PyNWB supports NWB files version 2 and above." %
    302                         str(file_version_str))
    303 # read the file
--> 304 file = super().read(**kwargs)
    305 return file

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/backends/hdf5/h5tools.py:479, in HDF5IO.read(self, **kwargs)
    476     raise UnsupportedOperation("Cannot read from file %s in mode '%s'. Please use mode 'r', 'r+', or 'a'."
    477                                % (self.source, self.__mode))
    478 try:
--> 479     return super().read(**kwargs)
    480 except UnsupportedOperation as e:
    481     if str(e) == 'Cannot build data. There are no values.':  # pragma: no cover

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/backends/io.py:60, in HDMFIO.read(self, **kwargs)
     57 if all(len(v) == 0 for v in f_builder.values()):
     58     # TODO also check that the keys are appropriate. print a better error message
     59     raise UnsupportedOperation('Cannot build data. There are no values.')
---> 60 container = self.__manager.construct(f_builder)
     61 container.read_io = self
     62 if self.herd_path is not None:

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/manager.py:284, in BuildManager.construct(self, **kwargs)
    280     result = self.__type_map.construct(builder, self, parent)
    281 else:
    282     # we are at the top of the hierarchy,
    283     # so it must be time to resolve parents
--> 284     result = self.__type_map.construct(builder, self, None)
    285     self.__resolve_parents(result)
    286 self.prebuilt(result, builder)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/manager.py:795, in TypeMap.construct(self, **kwargs)
    793     raise ValueError('No ObjectMapper found for builder of type %s' % dt)
    794 else:
--> 795     return obj_mapper.construct(builder, build_manager, parent)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1228, in ObjectMapper.construct(self, **kwargs)
   1226 cls = manager.get_cls(builder)
   1227 # gather all subspecs
-> 1228 subspecs = self.__get_subspec_values(builder, self.spec, manager)
   1229 # get the constructor argument that each specification corresponds to
   1230 const_args = dict()

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1157, in ObjectMapper.__get_subspec_values(self, builder, spec, manager)
   1155                 ret[subspec] = self.__flatten(sub_builder, subspec, manager)
   1156     # now process groups and datasets
-> 1157     self.__get_sub_builders(groups, spec.groups, manager, ret)
   1158     self.__get_sub_builders(datasets, spec.datasets, manager, ret)
   1159 elif isinstance(spec, DatasetSpec):

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1208, in ObjectMapper.__get_sub_builders(self, sub_builders, subspecs, manager, ret)
   1205     continue
   1206 if dt is None:
   1207     # recurse
-> 1208     ret.update(self.__get_subspec_values(sub_builder, subspec, manager))
   1209 else:
   1210     ret[subspec] = manager.construct(sub_builder)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1157, in ObjectMapper.__get_subspec_values(self, builder, spec, manager)
   1155                 ret[subspec] = self.__flatten(sub_builder, subspec, manager)
   1156     # now process groups and datasets
-> 1157     self.__get_sub_builders(groups, spec.groups, manager, ret)
   1158     self.__get_sub_builders(datasets, spec.datasets, manager, ret)
   1159 elif isinstance(spec, DatasetSpec):

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1210, in ObjectMapper.__get_sub_builders(self, sub_builders, subspecs, manager, ret)
   1208     ret.update(self.__get_subspec_values(sub_builder, subspec, manager))
   1209 else:
-> 1210     ret[subspec] = manager.construct(sub_builder)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/manager.py:280, in BuildManager.construct(self, **kwargs)
    278 if parent_builder is not None:
    279     parent = self._get_proxy_builder(parent_builder)
--> 280     result = self.__type_map.construct(builder, self, parent)
    281 else:
    282     # we are at the top of the hierarchy,
    283     # so it must be time to resolve parents
    284     result = self.__type_map.construct(builder, self, None)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/manager.py:795, in TypeMap.construct(self, **kwargs)
    793     raise ValueError('No ObjectMapper found for builder of type %s' % dt)
    794 else:
--> 795     return obj_mapper.construct(builder, build_manager, parent)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/utils.py:664, in docval.<locals>.dec.<locals>.func_call(*args, **kwargs)
    662 def func_call(*args, **kwargs):
    663     pargs = _check_args(args, kwargs)
--> 664     return func(args[0], **pargs)

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:1249, in ObjectMapper.construct(self, **kwargs)
   1247 for const_arg in get_docval(cls.__init__):
   1248     argname = const_arg['name']
-> 1249     override = self.__get_override_carg(argname, builder, manager)
   1250     if override is not None:
   1251         val = override

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/hdmf/build/objectmapper.py:532, in ObjectMapper.__get_override_carg(self, *args)
    530     self.logger.debug("        Calling override function for constructor argument '%s'" % name)
    531     func = self.constructor_args[name]
--> 532     return func(self, *remaining_args)
    533 return None

File ~/.pyenv/versions/miniconda3-latest/envs/dataproc-dev/lib/python3.9/site-packages/pynwb/io/epoch.py:20, in TimeIntervalsMap.columns_carg(self, builder, manager)
     17 timeseries_builder = builder.get('timeseries')
     18 # if we have a timeseries column and the type is VectorData instead of TimeSeriesReferenceVectorData
     19 if (timeseries_builder is not None and
---> 20         [HIDDEN]):
     21     # override builder attributes
     22     timeseries_builder.attributes['neurodata_type'] = 'TimeSeriesReferenceVectorData'
     23     timeseries_builder.attributes['namespace'] = 'core'

AttributeError: 'LinkBuilder' object has no attribute 'attributes'
```


### Operating System

macOS

### Python Executable

Conda

### Python Version

3.9

### Package Versions

pynwb                     2.5.0              pyh267d04e_0    conda-forge
hdmf                      3.10.0             pyh1ea47a8_0    conda-forge

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/.github/CODE_OF_CONDUCT.rst)
- [X] Have you checked the [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?

### Additional contract requirements

- Reading a copied NWBFile that contains a TimeSeriesReference in its trials table and linked TimeSeries data must succeed.
- After reading, the TimeSeriesReference must still refer to the corresponding TimeSeries in the file's acquisition table.
