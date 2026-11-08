BUG: df.query("`1` == 0.1") failed with UndefinedVariableError: name 'BACKTICK_QUOTED_STRING_1' is not defined
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

df = pd.DataFrame({1:[0.1, 0.2]})
df.query("`1` == 0.1")
```


### Issue Description

The above code raise a UndefinedVariableError: name 'BACKTICK_QUOTED_STRING_1' is not defined


### Expected Behavior

returns the first row

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.10.14
python-bits           : 64
OS                    : Linux
OS-release            : 5.15.0-122-generic
Version               : #132-Ubuntu SMP Thu Aug 29 13:45:52 UTC 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0
pip                   : 24.0
Cython                : 3.0.7
sphinx                : 7.3.7
IPython               : 8.25.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.6.0
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.4
lxml.etree            : None
matplotlib            : 3.9.2
numba                 : 0.60.0
numexpr               : 2.10.0
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : None
psycopg2              : 2.9.9
pymysql               : 1.4.6
pyarrow               : 16.1.0
pyreadstat            : None
pytest                : 8.2.2
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.0
sqlalchemy            : 2.0.31
tables                : 3.9.2
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : 0.22.0
tzdata                : 2024.1
qtpy                  : 2.4.1
pyqt5                 : None
</details>
