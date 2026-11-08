BUG: `ListAccessor` does not preserve series name
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
import pyarrow as pa

df = pd.DataFrame({
    "a": [[1,2,3], [4,5]],
    "b": ["hello", "pandas"]
}).astype({"a": pd.ArrowDtype(pa.list_(pa.int64()))})

df["a"].list.len().name, df["b"].str.len().name
# (None, "b")
```


### Issue Description

`ListAccessor` nullifies the series name (`list.len()` is just an example, other available methods lead to the same outcome).

### Expected Behavior

Series name to be preserved, as per other accessor (see `.str.len()` in the example)

### Installed Versions

TL;DR for relevant:
pandas                : 2.2.3
pyarrow               : 18.1.0
numpy                 : 2.1.3


INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.12.2
python-bits           : 64
OS                    : Linux
OS-release            : 5.15.133.1-microsoft-standard-WSL2
Version               : #1 SMP Thu Oct 5 21:02:42 UTC 2023
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : C.UTF-8
LOCALE                : C.UTF-8

pandas                : 2.2.3
numpy                 : 2.1.3
pytz                  : 2024.2
dateutil              : 2.9.0.post0
pip                   : None
Cython                : None
sphinx                : None
IPython               : 8.29.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.10.0
html5lib              : None
hypothesis            : 6.122.1
gcsfs                 : None
jinja2                : 3.1.4
lxml.etree            : None
matplotlib            : 3.9.3
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : 18.1.0
pyreadstat            : None
pytest                : 8.3.4
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.1
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : 2.0.1
xlsxwriter            : None
zstandard             : None
tzdata                : 2024.2
qtpy                  : None
pyqt5                 : None
