BUG: read_csv throws TypeError with iterator, nrows
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
from io import BytesIO
import pandas

csv = b'a,b\n1,2\n3,4'
with BytesIO(csv) as f:
    it = pd.read_csv(
                f,
                nrows=1,
                iterator=True,
            )
    for df in it:
        pass
```

Behavior:

```
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[82], line 11
      5 with BytesIO(csv) as f:
      6     it = pd.read_csv(
      7                 f,
      8                 nrows=1,
      9                 iterator=True,
     10             )
---> 11     for df in it:
     12         pass

[HIDDEN]

TypeError: '<' not supported between instances of 'int' and 'NoneType'
```
```


### Issue Description

It seems that `read_csv` throws a `TypeError` when combining `nrows` and `iterable`.


My context: I want to convert a CSV to parquet. The CSV is larger than memory, so I want to use `iterator=True`. The CSV contains a footer. But since `skipfooter` is not supported for the fast engines (c or pyarrow), and `comment` can only be a single character, I want to instead indirectly skip the footer by using `nrows`. (I know in advance the number of rows.) My data contains `\r\n` line endings, although the error happens with normal `\n`.

### Expected Behavior

The script runs without error. `nrows` rows of data are returned (across one chunk in this small example).

### Installed Versions

<details>
INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.11.9.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 142 Stepping 12, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_Australia.1252

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 69.5.1
pip                   : 24.0
Cython                : None
pytest                : 7.4.4
hypothesis            : None
sphinx                : 7.3.7
blosc                 : None
feather               : 0.4.1
xlsxwriter            : 3.2.0
lxml.etree            : 5.2.1
html5lib              : 1.1
pymysql               : None
psycopg2              : None
jinja2                : 3.1.4
IPython               : 8.25.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.2
bottleneck            : 1.3.7
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.3.1
gcsfs                 : None
matplotlib            : 3.8.4
numba                 : 0.59.1
numexpr               : 2.8.7
odfpy                 : None
openpyxl              : 3.1.2
pandas_gbq            : None
pyarrow               : 14.0.2
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : 2024.3.1
scipy                 : 1.13.1
sqlalchemy            : 2.0.30
tables                : 3.9.2
tabulate              : 0.9.0
xarray                : 2023.6.0
xlrd                  : 2.0.1
zstandard             : 0.22.0
tzdata                : 2023.3
qtpy                  : 2.4.1
pyqt5                 : None
</details>
