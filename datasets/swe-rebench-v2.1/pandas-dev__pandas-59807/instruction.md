BUG: replace with 3 or more `None` values fails when copy_on_write is enabled
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
pd.DataFrame({'mycol' : ['one','two']}).replace({'mycol': {'<NA>': None, 'null': None, '': None}}) #  all good
pd.options.mode.copy_on_write = True
pd.DataFrame({'mycol' : ['one','two']}).replace({'mycol': {'<NA>': None, 'null': None, '': None}}) # error
```


### Issue Description

When enabling copy_on_write, if you replace dictionary has 3 or more `None` values, it will return an error.

Interestingly, if you use two, it works:

```python
import pandas as pd
pd.DataFrame({'mycol' : ['one','two']}).replace({'mycol': {'<NA>': None, 'null': None, '': None}}) #  all good
pd.options.mode.copy_on_write = True
pd.DataFrame({'mycol' : ['one','two']}).replace({'mycol': {'<NA>': None, 'null': None, '': None}}) # error
pd.DataFrame({'mycol' : ['one','two']}).replace({'mycol': {'<NA>': None, 'null': None}}) # works
```

Also, if you use `pd.NA` instead of `None`, it also works

### Expected Behavior

Normal replacement, just like when `copy_on_write` is not enabled

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.10.14.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 5.15.0-1064-azure
Version               : #73~20.04.1-Ubuntu SMP Mon May 6 09:43:44 UTC 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : C.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.2
numpy                 : 2.1.1
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 70.1.1
pip                   : 24.0
Cython                : None
pytest                : 8.2.2
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : None
html5lib              : None
pymysql               : None
psycopg2              : None
jinja2                : 3.1.4
IPython               : 8.26.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2023.10.0
gcsfs                 : None
matplotlib            : 3.9.2
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : None
pyarrow               : None
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.1
sqlalchemy            : 2.0.31
tables                : None
tabulate              : 0.9.0
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None

</details>

### Additional contract requirements

- When none of the values to replace are present and `value=None`, the returned frame is unchanged and shares memory with the source frame under copy-on-write.
