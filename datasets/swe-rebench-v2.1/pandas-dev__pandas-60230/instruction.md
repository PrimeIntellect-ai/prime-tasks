BUG: Dataframe.to_excel treats decimal.Decimal as string instead of numeric type, the data in the Excel cell is formatted as a string, not a number
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the main branch of pandas.


### Reproducible Example

```python
# ----------------------------------
### imports

import pandas as pd
import decimal as dc

# ----------------------------------
### definitions

value_str = '2.445'

# ----------------------------------
### initialization

df_float = pd.DataFrame(data=[float(value_str)])
df_decimal = pd.DataFrame(data=[dc.Decimal(value_str)])

# ----------------------------------
### exports

# excel
df_float.to_excel('float.xlsx')
df_decimal.to_excel('decimal.xlsx')
```


### Issue Description

The code writes value to float.xlsx as number, but it is written as string in decimal.xlsx.

I identified that in the condition here https://github.com/pandas-dev/pandas/blob/d56f6e2bca75f10bc490aa320c4e1bc295e367bd/pandas/io/excel/_base.py#L1367 decimal.Decimal datatype is not treated, and it is converted to string. [HIDDEN], but it will require testing if excel writing libraries can handle it.

This same issue was already raised, but it was closed with no solution (by error?) https://github.com/pandas-dev/pandas/issues/26277

### Expected Behavior

Values in both dataframes should be written to excel as number.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit           : 91111fd99898d9dcaa6bf6bedb662db4108da6e6
python           : 3.9.13.final.0
python-bits      : 64
OS               : Linux
OS-release       : 6.0.5-200.fc36.x86_64
Version          : #1 SMP PREEMPT_DYNAMIC Wed Oct 26 15:55:21 UTC 2022
machine          : x86_64
processor        : x86_64
byteorder        : little
LC_ALL           : None
LANG             : en_GB.UTF-8
LOCALE           : en_GB.UTF-8

pandas           : 1.5.1
numpy            : 1.23.4
pytz             : 2022.6
dateutil         : 2.8.2
setuptools       : 65.5.1
pip              : 22.3.1
Cython           : None
pytest           : None
hypothesis       : None
sphinx           : None
blosc            : None
feather          : None
xlsxwriter       : None
lxml.etree       : None
html5lib         : None
pymysql          : None
psycopg2         : None
jinja2           : None
IPython          : None
pandas_datareader: None
bs4              : None
bottleneck       : None
brotli           : None
fastparquet      : None
fsspec           : None
gcsfs            : None
matplotlib       : None
numba            : None
numexpr          : None
odfpy            : None
openpyxl         : 3.0.10
pandas_gbq       : None
pyarrow          : None
pyreadstat       : None
pyxlsb           : None
s3fs             : None
scipy            : None
snappy           : None
sqlalchemy       : None
tables           : None
tabulate         : None
xarray           : None
xlrd             : None
xlwt             : None
zstandard        : None
tzdata           : None

</details>
