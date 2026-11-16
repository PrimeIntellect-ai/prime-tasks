BUG: pandas 2.2 read_csv(engine="c") leaks memory when code uses np.nan
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import numpy as np

import pandas as pd

pcp = np.ones((2700, 6100), dtype=np.float64)
# Comment the following line out, and the memory leak goes away
pcp[pcp < 0] = np.nan

for _ in range(1000):
    pd.read_csv("example.txt", engine="c")
```


### Issue Description

I upgraded my env to pandas 2.2 and my previously working script that does thousands of `read_csv` calls failed with OOM.  I trimmed everything down and to my amazement, found that the memory leak is triggered by the code usage of `np.nan`.  The above will use 3.2GB of RSS with `np.nan` used, 160 MB when not.  I can't believe this is even possible :)  Switching to engine="python" and there is no leak.

I can reproduce this on a clean conda-forge install `mamba create -n repro python=3.11 numpy pandas` on linux64.

### Expected Behavior

No leak or small/manageable memory leaks with each `read_csv` call.

### Installed Versions

<details>

/opt/miniconda3/envs/prod/lib/python3.11/site-packages/_distutils_hack/__init__.py:33: UserWarning: Setuptools is replacing distutils.
  warnings.warn("Setuptools is replacing distutils.")

INSTALLED VERSIONS
------------------
commit                : f538741432edf55c6b9fb5d0d496d2dd1d7c2457
python                : 3.11.7.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 5.14.0-410.el9.x86_64
Version               : #1 SMP PREEMPT_DYNAMIC Thu Jan 18 20:27:59 UTC 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.0
numpy                 : 1.26.3
pytz                  : 2023.3.post1
dateutil              : 2.8.2
setuptools            : 69.0.3
pip                   : 23.3.2
Cython                : 3.0.7
pytest                : 7.4.4
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : 3.1.9
lxml.etree            : 5.1.0
html5lib              : None
pymysql               : None
psycopg2              : 2.9.9
jinja2                : 3.1.3
IPython               : 8.20.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2023.12.2
gcsfs                 : None
matplotlib            : 3.8.2
numba                 : 0.58.1
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.2
pandas_gbq            : None
pyarrow               : 14.0.2
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : 2023.12.2
scipy                 : 1.12.0
sqlalchemy            : 2.0.25
tables                : None
tabulate              : None
xarray                : 2024.1.0
xlrd                  : 2.0.1
zstandard             : None
tzdata                : 2023.4
qtpy                  : 2.4.1
pyqt5                 : None
</details>
