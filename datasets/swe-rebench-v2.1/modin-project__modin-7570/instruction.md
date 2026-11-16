BUG: Dataframe.dtypes is NaN for empty Dataframes with pyarrow dtypes
### Modin version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest released version of Modin.

- [x] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
import modin.pandas as pd
import pyarrow as pa

df = pd.DataFrame({"A": []}, dtype=pd.ArrowDtype(pa.int64()))
print(df.dtypes["A"], type(df.dtypes["A"]))
```

### Issue Description

When creating an empty Dataframe with pyarrow dtypes, the dtype ends up as NaN.

### Expected Behavior

The returned dtypes should be the pyarrow dtype used when the Dataframe was created.

### Error Logs

<details>

```python-traceback

nan <class 'numpy.float64'>

```

</details>


### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 994221012c8738cf2da5b0b2a0f07a22749e63ee
python                : 3.12.10
python-bits           : 64
OS                    : Darwin
OS-release            : 24.5.0
Version               : Darwin Kernel Version 24.5.0: Tue Apr 22 19:54:49 PDT 2025; root:xnu-11417.121.6~2/RELEASE_ARM64_T6000
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : en_US.UTF-8
Modin dependencies
------------------
modin                 : 0.32.0+63.g99422101.dirty
ray                   : 2.46.0
dask                  : 2025.5.0
distributed           : 2025.5.0
pandas dependencies
-------------------
pandas                : 2.2.3
numpy                 : 2.2.5
pytz                  : 2025.2
dateutil              : 2.9.0.post0
pip                   : 25.1.1
Cython                : None
sphinx                : 8.2.3
IPython               : 9.2.0
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
lxml.etree            : 5.4.0
matplotlib            : 3.10.3
numba                 : None
numexpr               : 2.10.2
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : 0.28.0
psycopg2              : 2.9.9
pymysql               : None
pyarrow               : 20.0.0
pyreadstat            : None
pytest                : 8.3.5
python-calamine       : None
pyxlsb                : None
s3fs                  : 2025.3.2
scipy                 : 1.15.2
sqlalchemy            : 2.0.40
tables                : 3.10.2
tabulate              : 0.9.0
xarray                : 2025.4.0
xlrd                  : 2.0.1
xlsxwriter            : None
zstandard             : 0.23.0
tzdata                : 2025.2
qtpy                  : None
pyqt5                 : None
</details>
