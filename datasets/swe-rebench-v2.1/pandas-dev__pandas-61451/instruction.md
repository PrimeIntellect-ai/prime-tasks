BUG: `DataFrame` constructor not compatible with array-like classes that have a `'name'`  attribute
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import numpy as np
import pandas as pd
import vtk

poly = vtk.vtkPolyData(points=np.eye(3))
pd.DataFrame(poly.points)
```

``` python
ValueError: Per-column arrays must each be 1-dimensional

```
Originally posted in https://github.com/pyvista/pyvista/issues/7519

### Issue Description

Wrapping a `DataFrame` with the array-like object above results in an unexpected `ValueError` being raised. [HIDDEN]

https://github.com/pandas-dev/pandas/blob/41968a550a159ec0e5ef541a610b7007003bab5b/pandas/core/frame.py#L798-L799

This assumption fails for the `VTKArray` `poly.points`, which also has a `'name'` attribute.

### Expected Behavior

No error should be raised, and the array-like input should be wrapped correctly by `DataFrame`

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.12.2
python-bits           : 64
OS                    : Darwin
OS-release            : 23.4.0
Version               : Darwin Kernel Version 23.4.0: Fri Mar 15 00:19:22 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8112
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : en_CA.UTF-8
pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2025.2
dateutil              : 2.9.0.post0
pip                   : 25.1.1
Cython                : None
sphinx                : 8.1.3
IPython               : 8.36.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.4
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : 6.131.9
gcsfs                 : None
jinja2                : 3.1.6
lxml.etree            : None
matplotlib            : 3.10.1
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : 8.3.5
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.1
sqlalchemy            : None
tables                : None
tabulate              : 0.9.0
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2025.2
qtpy                  : None
pyqt5                 : None


</details>

### Additional contract requirements

- The `DataFrame` constructor must wrap the reported array-like input correctly without raising an error merely because it has a `name` attribute.
