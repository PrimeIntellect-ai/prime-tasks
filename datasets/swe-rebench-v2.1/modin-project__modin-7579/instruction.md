BUG: Using extensions to override a cached_property causes an error
### Modin version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest released version of Modin.

- [x] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
import modin.pandas as pd
from modin.pandas.api.extensions import (
    register_dataframe_groupby_accessor,
)
from functools import cached_property

@register_dataframe_groupby_accessor("groups")
@cached_property
def groups(self):
    return {0: pd.Index([0])}

pd.DataFrame([1]).groupby(0).groups()
```

### Issue Description

The above code raises `TypeError: Cannot use cached_property instance without calling __set_name__ on it.`

When `functools.cached_property` outside of a class definition, it seems to be unable to identify the class it should be bound to. Since `cached_property` uses the object's `__dict__` as a cache, [HIDDEN]

This issue is similar to this SO post: https://stackoverflow.com/questions/62160411/pythons-new-functools-cached-property-bug-or-limitation

### Expected Behavior

Should not error.

### Error Logs

<details>

```python-traceback

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/joshi/code/modin/modin/pandas/groupby.py", line 279, in __getattribute__
    extensions_result = self._getattribute__from_extension_impl(
  File "/Users/joshi/code/modin/modin/core/storage_formats/pandas/query_compiler_caster.py", line 344, in _getattribute__from_extension_impl
    extension.__get__(self) if hasattr(extension, "__get__") else extension
  File "/Users/joshi/miniconda3/envs/modin-dev/lib/python3.10/functools.py", line 965, in __get__
    raise TypeError(
TypeError: Cannot use cached_property instance without calling __set_name__ on it.

```

</details>


### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 5bc025e5303196b4bf7a0dc41da53d141969feae
python                : 3.10.13.final.0
python-bits           : 64
OS                    : Darwin
OS-release            : 24.5.0
Version               : Darwin Kernel Version 24.5.0: Tue Apr 22 19:54:25 PDT 2025; root:xnu-11417.121.6~2/RELEASE_ARM64_T6020
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

Modin dependencies
------------------
modin                 : 0.32.0+67.g5bc025e5
ray                   : 2.34.0
dask                  : 2024.8.1
distributed           : 2024.8.1

pandas dependencies
-------------------
pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2023.3.post1
dateutil              : 2.8.2
setuptools            : 68.0.0
pip                   : 23.3
Cython                : None
pytest                : 8.3.2
hypothesis            : None
sphinx                : 5.3.0
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : 5.3.0
html5lib              : None
pymysql               : None
psycopg2              : 2.9.9
jinja2                : 3.1.4
IPython               : 8.17.2
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.2
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : 2024.5.0
fsspec                : 2024.6.1
gcsfs                 : None
matplotlib            : 3.9.2
numba                 : None
numexpr               : 2.10.1
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : 0.23.1
pyarrow               : 17.0.0
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : 2024.6.1
scipy                 : 1.14.1
sqlalchemy            : 2.0.32
tables                : 3.10.1
tabulate              : 0.9.0
xarray                : 2024.7.0
xlrd                  : 2.0.1
zstandard             : None
tzdata                : 2023.3
qtpy                  : None
pyqt5                 : None
</details>

### Additional contract requirements

- Registering a `functools.cached_property` as a groupby extension must allow accessing the extension to return its computed value without raising the reported `__set_name__` TypeError.
