BUG: Series.duplicated doesn't preserve Series name
### Modin version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the latest released version of Modin.

- [ ] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
In [1]: import modin.pandas as pd

In [2]: pd.Series([1,2,3], name='a').duplicated()
Out[2]:
0    False
1    False
2    False
dtype: bool

In [3]: pd.Series([1,2,3], name='a').duplicated().name
```


### Issue Description

The name is not preserved

I noticed this in [Narwhals](https://github.com/narwhals-dev/narwhals/pull/870)

### Expected Behavior

pandas preserves the name:
```
In [1]: import pandas as pd

In [2]: pd.Series([1,2,3], name='a').duplicated().name
Out[2]: 'a'
```

### Error Logs

<details>

```python-traceback

Replace this line with the error backtrace (if applicable).

```

</details>


### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : c8bbca8e4e00c681370e3736b2f73bb0352408c3
python                : 3.11.9.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 5.15.153.1-microsoft-standard-WSL2
Version               : #1 SMP Fri Mar 29 23:14:13 UTC 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : C.UTF-8
LOCALE                : en_US.UTF-8

Modin dependencies
------------------
modin                 : 0.31.0
ray                   : None
dask                  : 2024.8.1
distributed           : 2024.8.1

pandas dependencies
-------------------
pandas                : 2.2.2
numpy                 : 2.1.0
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : None
pip                   : None
Cython                : None
pytest                : 8.3.2
hypothesis            : 6.111.2
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
bs4                   : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.6.1
gcsfs                 : None
matplotlib            : None
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
pyarrow               : 17.0.0
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.1
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
