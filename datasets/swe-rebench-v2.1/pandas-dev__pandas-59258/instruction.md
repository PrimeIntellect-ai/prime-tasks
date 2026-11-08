BUG: Passing an empty Index to pd.DataFrame.from_records() produces a ValueError
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

empty_df = pd.DataFrame([])  # works
df = pd.DataFrame([], index=empty_df.index)  # works
df = pd.DataFrame([], index=[])  # works
df = pd.DataFrame.from_records([])  # works
df = pd.DataFrame.from_records([], index=empty_df.index)  # raises ValueError
df = pd.DataFrame.from_records([], index=[])  # raises ValueError
```


### Issue Description

Passing an empty list or Index to the `index` parameter of `pd.DataFrame.from_records()` leads to
`ValueError: Must pass non-zero number of levels/codes`. This is true even if one passes an empty list of records to the method.

This is surprising for a couple of reasons. First, the lengths of the records and the index match, so it seems as though it should work properly. Second, as shown above, the `DataFrame` constructor doesn't complain when I pass an empty list or Index to its `index` parameter.

Finally, the documentation for `from_records()` describes the `index` parameter as, "Field of array to use as the index, alternately a specific set of input labels to use." Intuitively, an empty set should be acceptable when there's an empty list of input data.

### Expected Behavior

No error

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.12.2.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 165 Stepping 3, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United States.1252

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : None
pip                   : 24.0
Cython                : None
pytest                : None
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : None
html5lib              : None
pymysql               : None
psycopg2              : None
jinja2                : None
IPython               : None
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
gcsfs                 : None
matplotlib            : None
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
pyarrow               : None
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None

</details>
