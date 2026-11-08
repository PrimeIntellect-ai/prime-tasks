BUG: getting extension property that should raise AttributeError instead gets the property itself
### Modin version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest released version of Modin.

- [x] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
from modin.pandas.api.extensions import register_base_accessor
import modin.pandas as pd
import pytest

def _get_property(self):
    raise AttributeError


register_base_accessor('new_property')(property(_get_property))
df = pd.DataFrame()
df.new_property

with pytest.raises(AttributeError):
    df.new_property
```

### Issue Description

if getting an extension property should raise `AttributeError`, modin returns the `property` object itself instead of raise the same error.

[HIDDEN]

[HIDDEN]

### Expected Behavior

should raise `AttributeError`

### Error Logs

N/A

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 837fb954b7e05555652546e8bd68b63ddcf65e09
python                : 3.9.21
python-bits           : 64
OS                    : Darwin
OS-release            : 24.4.0
Version               : Darwin Kernel Version 24.4.0: Fri Apr 11 18:33:39 PDT 2025; root:xnu-11417.101.15~117/RELEASE_ARM64_T6020
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

Modin dependencies
------------------
modin                 : 0.32.0+58.g837fb954.dirty
ray                   : 2.44.1
dask                  : 2024.8.0
distributed           : 2024.8.0

pandas dependencies
-------------------
pandas                : 2.2.3
numpy                 : 2.0.2
pytz                  : 2025.2
dateutil              : 2.9.0.post0
pip                   : 24.2
Cython                : None
sphinx                : 7.4.7
IPython               : 8.18.1
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.4
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : 2024.11.0
fsspec                : 2025.3.2
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.6
lxml.etree            : 5.3.2
matplotlib            : 3.9.4
numba                 : None
numexpr               : 2.10.2
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : 0.28.0
psycopg2              : 2.9.10
pymysql               : None
pyarrow               : 19.0.1
pyreadstat            : None
pytest                : 8.3.5
python-calamine       : None
pyxlsb                : None
s3fs                  : 2025.3.2
scipy                 : 1.13.1
sqlalchemy            : 2.0.40
tables                : N/A
tabulate              : 0.9.0
xarray                : 2024.7.0
xlrd                  : 2.0.1
xlsxwriter            : None
zstandard             : None
tzdata                : 2025.2
qtpy                  : None
pyqt5                 : None

</details>
