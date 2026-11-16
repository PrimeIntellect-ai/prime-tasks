BUG: StataWriter returns ascii error when length of string is < 2045, but encoded length is > 2045
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

df = pd.DataFrame({'doubleByteCol': ['§'*1500]})
df.to_stata('temp.dta', version=118)

[HIDDEN]
```

### Issue Description

[HIDDEN]

### Expected Behavior

[HIDDEN]

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.12.1.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 11
Version               : 10.0.26100
machine               : AMD64
processor             : AMD64 Family 25 Model 33 Stepping 0, AuthenticAMD
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : English_Belgium.1252

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : None
pip                   : 23.2.1
Cython                : None
pytest                : 8.3.5
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : 4.9.4
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
pyarrow               : 15.0.2
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

### Temporary fix
For users finding this topic, this refers to the following Exception
```
Exception has occurred: UnicodeEncodeError       (note: full exception trace is shown but execution is paused at: <module>)
'ascii' codec can't encode characters in position 0-1499: ordinal not in range(128)
  File "F:\datatog\junkyard\adhoc-scripts\mwes\pandas_asciiencoding.py", line 4, in <module> (Current frame)
    df.to_stata('temp.dta', version=118)
UnicodeEncodeError: 'ascii' codec can't encode characters in position 0-1499: ordinal not in range(128)
```

You can workaround this issue by explicitly specifying the offending columns in the `convert_strL` option.

### Additional contract requirements

- When a string’s character length is below Stata’s 2045-byte short-string limit but its UTF-8 encoded length exceeds that limit (for example, 1,500 `§` characters), `DataFrame.to_stata` must complete without an encoding error and preserve the original string in the exported data.
