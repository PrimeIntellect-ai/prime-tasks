BUG: queries on categorical string columns in HDFStore.select() return unexpected results
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

models = pd.api.types.CategoricalDtype(categories=['name','longname','verylongname'])
df = pd.DataFrame({'modelId':['name','longname','longname'],
                   'value'  :[1,2,3]}
                ).astype({'modelId':models,'value':int})
with pd.HDFStore('test.h5','w') as store:
    store.append('df',df,data_columns=['modelId'])

with pd.HDFStore('test.h5','r') as store:

    model = 'name'
    print(store.select('df', 'modelId == model'))

    model = 'longname'
    print(store.select('df', 'modelId == model'))

    model = 'verylongname'
    print(store.select('df', 'modelId == model'))
```


### Issue Description

This seems to be the same or very similar to bug #39189 (regression?)

I encountered the same behavior under pandas 2.2.0 and 2.2.1

### Expected Behavior

The DataFrame stored in the HDF store is:

```
>>> df
0      name      1
1  longname      2
2  longname      3

```
The 3 print statements give:

```
# Below should have matched row 0 instead of Empty
>>> model = 'name'
>>> print(store.select('df', 'modelId == model'))
Empty DataFrame
Columns: [modelId, value]
Index: []

# Below matched row 0 but should have matched rows 1 and 2
>>> model = 'longname'
>>> print(store.select('df', 'modelId == model'))
  modelId  value
0    name      1

# This is correct
>>> model = 'verylongname'
>>> print(store.select('df', 'modelId == model'))
Empty DataFrame
Columns: [modelId, value]
Index: []
```

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : bdc79c146c2e32f2cab629be240f01658cfb6cc2
python                : 3.11.8.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 6.1.69-gentoo-dist-hardened
Version               : #1 SMP PREEMPT_DYNAMIC Thu Jan 18 22:03:57 CET 2024
machine               : x86_64
processor             : AMD Ryzen 5 3600X 6-Core Processor
byteorder             : little
LC_ALL                : en_US.UTF-8
LANG                  : en_BE.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.1
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.8.2
setuptools            : 69.0.3
pip                   : None
Cython                : 3.0.8
pytest                : 7.4.4
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : 3.1.9
lxml.etree            : 4.9.4
html5lib              : 1.1
pymysql               : None
psycopg2              : None
jinja2                : 3.1.3
IPython               : 8.21.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : 1.3.7
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.2.0
gcsfs                 : None
matplotlib            : 3.8.2
numba                 : 0.59.0
numexpr               : 2.9.0
odfpy                 : None
openpyxl              : 3.1.2
pandas_gbq            : None
pyarrow               : None
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.12.0
sqlalchemy            : 2.0.25
tables                : 3.9.2
tabulate              : 0.9.0
xarray                : 2024.1.1
xlrd                  : 2.0.1
zstandard             : 0.22.0
tzdata                : None
qtpy                  : 2.4.1
pyqt5                 : None

</details>
