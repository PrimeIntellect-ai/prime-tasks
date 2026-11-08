BUG: dot on Arrow Series produces a Numpy object result
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

series_result = pd.Series({"a": 1.0}, dtype="Float64").dot(
    pd.DataFrame({"col1": {"a": 2.0}, "col2": {"a": 3.0}}, dtype="Float64")
)
series_result.dtype  # is dtype('O')

series_result_2 = pd.Series({"a": 1.0}, dtype="float[pyarrow]").dot(
    pd.DataFrame({"col1": {"a": 2.0}, "col2": {"a": 3.0}}, dtype="float[pyarrow]")
)
series_result_2.dtype  # same, is dtype('O')

# `DataFrame.dot` was already fixed
df_result = pd.DataFrame({"col1": {"a": 2.0}, "col2": {"a": 3.0}}, dtype="Float64").T.dot(
    pd.Series({"a": 1.0}, dtype="Float64")
)
df_result.dtype  # is Float64Dtype()
```

### Issue Description

`Series.dot` with Arrow or nullable dtypes returns series result with numpy object dtype. This was reported in #53979 and fixed for DataFrames in #54025.

Possibly side notes: I believe the "real" issue here is that the implementation uses `.values` which returns a `dtype=object` array for the DataFrame. This seems directly related to #60038 and at least somewhat related to #60301 (which is also referenced in a comment on the former).

### Expected Behavior

I would expect `Series.dot` to return the "best" common datatype for the input datatypes (in the examples, would expect the appropriate float dtype)

```python
import pandas as pd

series_result = pd.Series({"a": 1.0}, dtype="Float64").dot(
    pd.DataFrame({"col1": {"a": 2.0}, "col2": {"a": 3.0}}, dtype="Float64")
)
series_result.dtype  # would expect Float64Dtype()

series_result_2 = pd.Series({"a": 1.0}, dtype="float[pyarrow]").dot(
    pd.DataFrame({"col1": {"a": 2.0}, "col2": {"a": 3.0}}, dtype="float[pyarrow]")
)
series_result_2.dtype  # would expect float[pyarrow]
```

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.11.12
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 85 Stepping 7, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United States.1252

pandas                : 2.2.3
numpy                 : 2.2.5
pytz                  : 2025.2
dateutil              : 2.9.0.post0
pip                   : 25.1
Cython                : None
sphinx                : 8.2.3
IPython               : 9.2.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.4
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2025.3.2
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.6
lxml.etree            : None
matplotlib            : 3.10.1
numba                 : 0.61.2
numexpr               : 2.10.2
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : None
psycopg2              : 2.9.9
pymysql               : None
pyarrow               : 19.0.1
pyreadstat            : None
pytest                : 8.3.5
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.15.2
sqlalchemy            : 2.0.40
tables                : 3.10.2
tabulate              : None
xarray                : None
xlrd                  : 2.0.1
xlsxwriter            : None
zstandard             : 0.23.0
tzdata                : 2025.2
qtpy                  : None
pyqt5                 : None

</details>
