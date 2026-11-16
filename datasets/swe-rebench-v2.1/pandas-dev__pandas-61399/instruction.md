BUG: round on object columns no longer raises a TypeError
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
df=pd.DataFrame(data=['foo'],columns=['bar'])
df.loc[0,'bar']=0.2
df['bar'].round()

Out[4]:
0    0.2
```

### Issue Description

pd.Series.round() appears to have changed behaviour in 2.2.3 compared to 2.1.4.
In previous versions, attempting to round a column with "object" dtype would raise a TypeError. In 2.2.3, round now silently returns the same column, without applying any rounding.

I'm not sure if there is some underlying change that causes this behaviour, but together with the removal of downcasting from a variety of methods (ffill, replace, fillna,...) this change in behaviour seems dangerous without any warnings.

### Expected Behavior

import pandas as pd
df=pd.DataFrame(data=['foo'],columns=['bar'])
df.loc[0,'bar']=0.2
df['bar'].round()

TypeError: loop of ufunc does not support argument 0 of type float which has no callable rint method

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.9.18
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 142 Stepping 12, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United Kingdom.1252
pandas                : 2.2.3
numpy                 : 1.26.3
pytz                  : 2023.3.post1
dateutil              : 2.8.2
pip                   : 23.3.1
Cython                : None
sphinx                : None
IPython               : 8.15.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.2
blosc                 : None
bottleneck            : 1.3.6
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.2
lxml.etree            : 4.9.3
matplotlib            : 3.8.0
numba                 : 0.60.0
numexpr               : 2.8.7
odfpy                 : None
openpyxl              : 3.1.0
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : 7.4.0
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.11.4
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : 2023.12.0
xlrd                  : 2.0.1
xlsxwriter            : 3.1.1
zstandard             : 0.19.0
tzdata                : 2023.3
qtpy                  : None
pyqt5                 : None


</details>
