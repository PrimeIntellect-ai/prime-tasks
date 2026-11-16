BUG: pd.to_numeric(timedelta_scalar) raises TypeError
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

pd.to_numeric(pd.Timedelta(1))
```


### Issue Description

Getting a `TypeError`

### Expected Behavior

For the example above, I should get the integer `1`. That would match the behavior of `pd.to_numeric(pd.Series(pd.Timedelta(1)))`

### Installed Versions

<details>

```
INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.9.18
python-bits           : 64
OS                    : Darwin
OS-release            : 23.6.0
Version               : Darwin Kernel Version 23.6.0: Wed Jul 31 20:48:52 PDT 2024; root:xnu-10063.141.1.700.5~1/RELEASE_ARM64_T6020
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.3
numpy                 : 1.26.3
pytz                  : 2023.3.post1
dateutil              : 2.8.2
pip                   : 23.3.1
Cython                : None
sphinx                : None
IPython               : 8.18.1
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : None
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : None
lxml.etree            : None
matplotlib            : None
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : 8.3.2
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2023.4
qtpy                  : None
pyqt5                 : None
```

</details>
