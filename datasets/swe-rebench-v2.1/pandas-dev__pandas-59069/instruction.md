BUG: None value in MultiIndex can't be found
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

indices = [["one"], ["a"], ["yes"]]
df = pd.DataFrame([0], index=indices).T
df["one", None, "yes"] = 1
print(df)
print()
print(df["one"])
print()
print(df["one"][None])
```


### Issue Description

The dataframe has an item at the multiindex of ["one", None, "yes"], but attempting to access it fails. It appears to only happen when I use None/nan values for the middle index that I'm adding, and it only happens if I add the value using the df[] = syntax.

### Expected Behavior

It should return a value when I query df["one"][None]. If I construct the dataframe with this data in it to begin with, or add it with a df.concat, it works.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.9.2.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 4.18.0-513.24.1.el8_9.x86_64
Version               : #1 SMP Thu Mar 14 14:20:09 EDT 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.2
numpy                 : 1.23.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 70.0.0
pip                   : 23.1
Cython                : None
pytest                : 7.4.4
hypothesis            : None
sphinx                : 7.3.7
blosc                 : None
feather               : None
xlsxwriter            : 3.2.0
lxml.etree            : 5.2.2
html5lib              : None
pymysql               : None
psycopg2              : None
jinja2                : 3.1.4
IPython               : 8.18.1
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.6.0
gcsfs                 : None
matplotlib            : 3.9.0
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.2
pandas_gbq            : None
pyarrow               : None
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : 2.0.12
tables                : None
tabulate              : None
xarray                : None
xlrd                  : 2.0.1
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None

</details>
