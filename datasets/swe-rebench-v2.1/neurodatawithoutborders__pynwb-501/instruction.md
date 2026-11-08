BehavioralEvents does not write to hdf5 file
Using minimal example below to create an nwb file and a BehavioralEvents time series, groups for the processing module and for the BehavioralEvents container are created. However, the data is missing from the hdf5 file after writing the data.

[HIDDEN]

    - ObjectMapper is reading from the wrong attribute.

### Steps to Reproduce
```
from datetime import datetime
import numpy as np
from pynwb.behavior import BehavioralEvents
from pynwb import NWBFile, NWBHDF5IO, TimeSeries

nwbfile = NWBFile(source='nwbfile_source',
                  session_description='nwb_file_session_description',
                  identifier='0',
                  session_start_time=datetime(2017, 5, 4, 1, 1, 1))

ts = TimeSeries(name='behavioral_events_name', source='behavioral_events_source',
                  data=[1.0,2.0,3.0,4.0],
                  timestamps=[5.0,6.0,7.0,8.0]
                  unit='ms',
                  resolution=np.nan,
                  conversion=np.nan)

behavioral_events = BehavioralEvents('Behavioral_Events_source',name='BehavioralEvents_name')
behavioral_events.add_timeseries(ts)

behavior_module = nwbfile.create_processing_module('behavioral_module_name',
                                                   'behavioral_module_source',
                                                   'example module')
behavior_module.add_container(behavioral_events)

with NWBHDF5IO('test_behavior.nwb', mode='w') as io:
   io.write(nwbfile)
```
### Environment
Please describe your environment according to the following bullet points.
- **Python Executable:** Python
- **Python Version:** Python 2.7
- **Operating System:** macOS
- **Pynwb Version:** 0.3.0

### Additional contract requirements

- `BehavioralEvents` exposes its contained `TimeSeries` objects through an indexable `time_series` mapping keyed by each `TimeSeries` name.
- Writing an NWB file containing a `BehavioralEvents` with an added `TimeSeries` must persist that `TimeSeries`, including its data and timestamps, so they are present when the file is read back.
