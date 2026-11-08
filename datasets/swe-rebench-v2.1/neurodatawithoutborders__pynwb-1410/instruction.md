add_intracellular_recording fails with IZeroClampSeries
## Description

`nwbfile.add_intracellular_recording()` fails when adding intracellular recordings for IZeroClampSeries.

## Steps to Reproduce

```python
from datetime import datetime
from dateutil.tz import tzlocal
import numpy as np
from pynwb import NWBFile, NWBHDF5IO
from pynwb.icephys import IZeroClampSeries

# Create an ICEphysFile
ex_nwbfile = NWBFile(
    session_description='my first recording',
    identifier='EXAMPLE_ID',
    session_start_time=datetime.now(tzlocal())
)

# Add a device
ex_device = ex_nwbfile.create_device(name='Heka ITC-1600')

# Add an intracellular electrode
ex_electrode = ex_nwbfile.create_icephys_electrode(
    name="elec0",
    description='a mock intracellular electrode',
    device=ex_device
)

# Create an ic-response
ex_response = IZeroClampSeries(
    name='response',
    data=[0.1, 0.2, 0.3, 0.4, 0.5],
    starting_time=123.6,
    rate=20e3,
    electrode=ex_electrode,
    gain=0.02,
)

ex_ir_index = ex_nwbfile.add_intracellular_recording(
    electrode=ex_electrode,
    response=ex_response
)
```

This yields:
```python
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
<ipython-input-1-64c6207e7322> in <module>
     32 )
     33
---> 34 ex_ir_index = ex_nwbfile.add_intracellular_recording(
     35     electrode=ex_electrode,
     36     response=ex_response

~/anaconda3/envs/env_icephys/lib/python3.8/site-packages/hdmf/utils.py in func_call(*args, **kwargs)
    581             def func_call(*args, **kwargs):
    582                 pargs = _check_args(args, kwargs)
--> 583                 return func(args[0], **pargs)
    584         else:
    585             def func_call(*args, **kwargs):

~/anaconda3/envs/env_icephys/lib/python3.8/site-packages/pynwb/file.py in add_intracellular_recording(self, **kwargs)
    804         # make sure the intracellular recordings table exists and if not create it using get_intracellular_recordings
    805         # Add the recoding to the intracellular_recordings table
--> 806         return call_docval_func(self.get_intracellular_recordings().add_recording, kwargs)
    807
    808     @docval(returns='The NWBFile.icephys_simultaneous_recordings table', rtype=SimultaneousRecordingsTable)

~/anaconda3/envs/env_icephys/lib/python3.8/site-packages/hdmf/utils.py in call_docval_func(func, kwargs)
    422 def call_docval_func(func, kwargs):
    423     fargs, fkwargs = fmt_docval_args(func, kwargs)
--> 424     return func(*fargs, **fkwargs)
    425
    426

~/anaconda3/envs/env_icephys/lib/python3.8/site-packages/hdmf/utils.py in func_call(*args, **kwargs)
    581             def func_call(*args, **kwargs):
    582                 pargs = _check_args(args, kwargs)
--> 583                 return func(args[0], **pargs)
    584         else:
    585             def func_call(*args, **kwargs):

~/anaconda3/envs/env_icephys/lib/python3.8/site-packages/pynwb/icephys.py in add_recording(self, **kwargs)
    529         if response.neurodata_type == 'IZeroClampSeries':
    530             if stimulus is not None:
--> 531                 raise ValueError("stimulus should usually be None for IZeroClampSeries response")
    532         if isinstance(response, PatchClampSeries) and isinstance(stimulus, PatchClampSeries):
    533             # # We could also check sweep_number, but since it is mostly relevant to the deprecated SweepTable

ValueError: stimulus should usually be None for IZeroClampSeries response
```

## Environment

- Python Executable: Conda environment, Jupyter Notebook
- Python Version: Python 3.8.11
- Operating System: Linux
- HDMF Version: 3.1.1
- PyNWB Version: 2.0.0

## Checklist

- [x] Have you ensured the bug was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues)?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?
