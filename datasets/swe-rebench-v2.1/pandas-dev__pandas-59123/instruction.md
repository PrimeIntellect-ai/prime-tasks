BUG: pivot_table chokes on pd.DatetimeTZDtype if there are no rows.
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
df = pd.DataFrame({'timestamp': [pd.Timestamp('2024-01-01T00:00', tz='UTC')], 'category': ['A'], 'value': [100]})
df[df.category == "C"].pivot_table(index="category", columns="value", values="timestamp")
```


### Issue Description

This raises an error `TypeError: Cannot interpret 'datetime64[ns, UTC]' as a data type`

### Expected Behavior

It should return an empty DataFrame.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.12.3.final.0
python-bits           : 64
OS                    : Darwin
OS-release            : 23.5.0
Version               : Darwin Kernel Version 23.5.0: Wed May  1 20:14:38 PDT 2024; root:xnu-10063.121.3~5/RELEASE_ARM64_T6020
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : fr_FR.UTF-8
LOCALE                : fr_FR.UTF-8

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 69.5.1
pip                   : 24.0
Cython                : None
pytest                : 8.2.1
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : 3.2.0
lxml.etree            : 5.2.1
html5lib              : None
pymysql               : None
psycopg2              : 2.9.9
jinja2                : 3.1.4
IPython               : 8.23.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.5.0
gcsfs                 : None
matplotlib            : 3.8.4
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.0
pandas_gbq            : None
pyarrow               : 16.1.0
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : 2024.5.0
scipy                 : None
sqlalchemy            : 2.0.30
tables                : None
tabulate              : 0.9.0
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None


</details>
