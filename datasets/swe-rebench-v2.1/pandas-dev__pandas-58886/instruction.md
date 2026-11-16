BUG: Rolling .apply() with method='table' ignores min_periods
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

df = pd.DataFrame([[1, 2], [3, 4], [5, 6], [7, 8], [9, 10]], columns=['A', 'B'])
print(df)

# prints this:
#    A   B
# 0  1   2
# 1  3   4
# 2  5   6
# 3  7   8
# 4  9  10

df.rolling(3, min_periods=3).apply(lambda x: bool(print(x, '\n')))

# prints this, so as expected, only batches of 3 are being evaluated
# 0    1.0
# 1    3.0
# 2    5.0
# dtype: float64
#
# 1    3.0
# 2    5.0
# 3    7.0
# dtype: float64
#
# 2    5.0
# 3    7.0
# 4    9.0
# dtype: float64
#
# 0    2.0
# 1    4.0
# 2    6.0
# dtype: float64
#
# 1    4.0
# 2    6.0
# 3    8.0
# dtype: float64
#
# 2     6.0
# 3     8.0
# 4    10.0
# dtype: float64
#
# Out[33]:
#      A    B
# 0  NaN  NaN
# 1  NaN  NaN
# 2  0.0  0.0
# 3  0.0  0.0
# 4  0.0  0.0

df.rolling(3, method='table', min_periods=3).apply(lambda x: bool(print(x, '\n')), raw=True, engine='numba')

# prints this, where we see that the first two batches of sizes 1 and 2 are also being evaluated
# [[1. 2.]]   <-- batch of size 1, illegal
#
# [[1. 2.]    <-- batch of size 2, illegal
#  [3. 4.]]
#
# [[1. 2.]
#  [3. 4.]
#  [5. 6.]]
#
# [[3. 4.]
#  [5. 6.]
#  [7. 8.]]
#
# [[ 5.  6.]
#  [ 7.  8.]
#  [ 9. 10.]]
# Out[34]:
#      A    B
# 0  NaN  NaN
# 1  NaN  NaN
# 2  0.0  0.0
# 3  0.0  0.0
# 4  0.0  0.0
```


### Issue Description

See example above, which violates the contract imposed by the `min_periods` parameter.

### Expected Behavior

The `min_periods` parameter should be respected.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.12.3.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 11
Version               : 10.0.22631
machine               : AMD64
processor             : Intel64 Family 6 Model 165 Stepping 2, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : German_Switzerland.utf8
pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0
setuptools            : 69.5.1
pip                   : 24.0
Cython                : None
pytest                : None
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : 5.2.2
html5lib              : 1.1
pymysql               : None
psycopg2              : None
jinja2                : 3.1.4
IPython               : 8.24.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
gcsfs                 : None
matplotlib            : 3.8.4
numba                 : 0.59.1
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
pyarrow               : 16.0.0
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.13.0
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
