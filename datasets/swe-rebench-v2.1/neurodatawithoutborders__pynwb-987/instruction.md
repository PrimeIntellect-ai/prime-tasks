bug in reading in nwb file with date_of_birth field in Subject() set
## 1) Bug

When setting the date_of_birth field in a subject object, the write of the nwb file works, but subsequently reading in the file gives the following error:

~/anaconda3/envs/default/lib/python3.6/site-packages/six.py in raise_from(value, from_value)

TypeError: incorrect type for 'date_of_birth' (got 'str', expected 'datetime')


### Steps to Reproduce
```python
from datetime import datetime
from dateutil.tz import tzlocal
import pynwb
import numpy as np

start_time = datetime(2017, 4, 3, 11, tzinfo=tzlocal())
create_date = datetime(2017, 4, 15, 12, tzinfo=tzlocal())

nwbf = pynwb.NWBFile(session_description='demonstrate NWBFile basics',  # required
                  identifier='NWB123',  # required
                  session_start_time=start_time,  # required
                  file_create_date=create_date)  # optional

nwbf.subject = pynwb.file.Subject(date_of_birth=start_time,
                                  description='Long Evans Rat',
                                  genotype='WT',
                                  sex='M',
                                  species='rat',
                                  subject_id='Bond',
                                  weight='unknown')

io = pynwb.NWBHDF5IO('example_file_path.nwb', mode='w')
io.write(nwbf)
io.close()

io = pynwb.NWBHDF5IO('example_file_path.nwb', 'r')
nwbf = io.read()
```
### Environment
Please describe your environment according to the following bullet points.
- **Python Executable:** Conda
- **Python Version:**  Python 3.6
- **Operating System:** , macOS
- **Pynwb Version:** current release
