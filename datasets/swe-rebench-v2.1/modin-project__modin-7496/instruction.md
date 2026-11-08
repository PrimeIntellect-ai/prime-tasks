BUG: dataframe extensions for some methods (possibly just aliased methods like pow?) are not working
### Modin version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest released version of Modin.

- [x] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
import modin.pandas as pd
from modin.pandas.api.extensions import register_dataframe_accessor
register_dataframe_accessor("pow")(lambda *args, **kwargs: 4)
result = pd.DataFrame([1]).pow(1)
assert isinstance(result, int)
```

### Issue Description

the override is not working.

### Expected Behavior

In the example, we should override the `pow` behavior for all backends.

### Error Logs

n/a

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d512c53e1ea032fba10d2ab1261ffd621940752d
python                : 3.9.21
python-bits           : 64
OS                    : Darwin
OS-release            : 24.3.0
Version               : Darwin Kernel Version 24.3.0: Thu Jan  2 20:24:23 PST 2025; root:xnu-11215.81.4~3/RELEASE_ARM64_T6020
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

Modin dependencies
------------------
modin                 : 0.32.0+33.gd512c53e
ray                   : 2.40.0
dask                  : 2024.8.0
distributed           : 2024.8.0

pandas dependencies
-------------------
pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2024.2
dateutil              : 2.8.2
pip                   : 24.2
Cython                : None
sphinx                : 5.3.0
IPython               : 8.18.1
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : 2024.11.0
fsspec                : 2024.12.0
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.5
lxml.etree            : 5.3.0
matplotlib            : 3.9.4
numba                 : None
numexpr               : 2.10.2
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : 0.26.1
psycopg2              : 2.9.10
pymysql               : None
pyarrow               : 19.0.0
pyreadstat            : None
pytest                : 8.3.4
python-calamine       : None
pyxlsb                : None
s3fs                  : 2024.12.0
scipy                 : 1.13.1
sqlalchemy            : 2.0.37
tables                : 3.9.2
tabulate              : 0.9.0
xarray                : 2024.7.0
xlrd                  : 2.0.1
xlsxwriter            : None
zstandard             : None
tzdata                : 2024.2
qtpy                  : None
pyqt5                 : None


</details>

### Additional contract requirements

- Registering a dataframe accessor override for a method must take effect for that exact method name. Aliased methods and their magic-method counterparts have independent extension sets: `pow`, `__pow__`, and `__ipow__` are registered separately, so registering an override for one of them must not change the behavior of the others. In particular, an override registered for `pow` must not affect `__pow__`, and an override registered for `__pow__` must not affect `pow`.
