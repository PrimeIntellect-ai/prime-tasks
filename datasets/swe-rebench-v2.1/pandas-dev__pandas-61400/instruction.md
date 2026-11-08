BUG: Incorrect Parsing of Timestamps in pd.to_datetime with Series with format="ISO8601"  and UTC=True
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

# Single timestamp
raw = "2023-10-15T14:30:00"
single = pd.to_datetime(raw, utc=True, format="ISO8601")
print(single)
# Output: 2023-10-15 14:30:00+00:00 (correct)

# Series of timestamps
series = pd.Series([0, 0], index=["2023-10-15T10:30:00-12:00", raw])
converted = pd.to_datetime(series.index, utc=True, format="ISO8601")
print(converted)
# Output: 2023-10-16 02:30:00+00:00 for the second one (incorrect)
# error depends on the previous one timezone
```

### Issue Description

When using pd.to_datetime to parse a Series of timestamps with format="ISO8601" and utc=True, the parsing of a timestamp without an explicit timezone offset is incorrect and appears to depend on the timezone offset of the previous timestamp in the Series. This behavior does not occur when parsing a single timestamp.

### Expected Behavior

In this configuration, behavior should not depend on the previous timestamp timezone. Result should be the same as when individually passed.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.10.0
python-bits           : 64
OS                    : Linux
OS-release            : 5.10.0-34-amd64
Version               : #1 SMP Debian 5.10.234-1 (2025-02-24)
machine               : x86_64
processor             :
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2024.2
dateutil              : 2.9.0.post0
pip                   : 24.2
Cython                : None
sphinx                : None
IPython               : None
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
jinja2                : 3.1.6
lxml.etree            : None
matplotlib            : 3.10.1
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : 15.0.2
pyreadstat            : None
pytest                : 8.3.5
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.15.2
sqlalchemy            : 2.0.40
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2025.2
qtpy                  : None
pyqt5                 : None
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
NameError: name 'version' is not defined

</details>
