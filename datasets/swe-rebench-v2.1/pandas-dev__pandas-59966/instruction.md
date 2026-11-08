BUG: Inconsistent treatment of NaNs when `.apply()` function is used on categorical columns
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

df = pd.DataFrame(
    {
        "a": [4, np.nan, 6],
        "b": ["one", "two", np.nan]
    }
)
df["b"] = df["b"].astype("category")

df["a'"] = df["a"].apply(lambda x: pd.notnull(x))  # rows with NaNs are treated
df["b'"] = df["b"].apply(lambda x: pd.notnull(x))  # rows with NaNs are skipped
display(df)
```


### Issue Description

There is an inconsistency in how `DataFrame.apply()` function works on columns with categorical data, vs columns with any other type of the data. Generally speaking, `.apply()` function is called for every row of data (assuming `axis=0` here), and then the user-defined function would be called on that row. This happens for all values of data, including NaNs, so if a special behaviour for NaNs is needed, it can be integrated easily. However, if the data column is of type `category`, the rows with NaNs appear to be automatically skipped, so rows with NaNs cannot be processed by the user.

In my opinion, this is a fundamental inconsistency, which I would call a bug. I would understand that in some situations the skipping of the NaN rows might be a preferred behaviour, but then it should probably be controllable via keyword arguments and certainly not datatype-dependent.

### Expected Behavior

```df["b'"] = df["b"].astype("string").apply(lambda x: pd.notnull(x))  # would work correctly...```

...but I don't quite understand why such a fundamental behavior needs to be dependent on the type of the data.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.11.3.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.22621
machine               : AMD64
processor             : AMD64 Family 25 Model 68 Stepping 1, AuthenticAMD
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United Kingdom.1252

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 69.0.2
pip                   : 23.3.1
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
IPython               : 8.26.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : 2024.5.0
fsspec                : 2024.6.1
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
