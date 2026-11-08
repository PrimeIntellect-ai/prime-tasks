BUG: get_level_values() in a MultiIndex returns DatetimeIndex without frequency even though the index level has a frequency (and unique values).
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
>>> import pandas as pd
>>> dates  = pd.date_range("2000", freq = 'YS', periods = 4)
>>> index = ["A"]
>>> multi_index = pd.MultiIndex.from_product([dates, index], names = [“Dates”, “Second Index”])
>>> print(multi_index.levels[0].freq)
<YearBegin: month=1>
>>> print(multi_index.get_level_values(0).freq)
None
>>> print(multi_index.get_level_values(“Dates”).freq)
None
```


### Issue Description

For a DatetimeIndex contained in a MultiIndex get_level_values() returns a DatetimeIndex without frequency, even if the frequency is set and available in the internal structure (i.e. if accessed via index.levels, see example above).

[HIDDEN]

Why (at least to me) it is important that this works correctly although it works with level[0].freq? With get_level_values() it is also possible to use the name as an identifier (not only the index level number), which in many cases is a lot more convenient.


### Expected Behavior

I would expect that get_level_values() returns a DatetimeIndex with correct frequency, mirroring the one actually set in the MultiIndex.


### Installed Versions

<details>

------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.9.13.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 85 Stepping 0, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United Kingdom.1252

pandas                : 2.2.2
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 69.2.0
pip                   : 24.0
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
IPython               : None
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
gcsfs                 : None
matplotlib            : None
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
pyarrow               : None
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None

<details>

### Additional contract requirements

- When a datetime-like level has a frequency, `MultiIndex.get_level_values` must return an index whose `.freq` matches that frequency, whether the level is selected by integer position or by name.


- When a datetime-like MultiIndex level has a frequency (for example a `DatetimeIndex` or a `TimedeltaIndex` level), `get_level_values` returns an index whose `.freq` equals that frequency, whether the level is selected by integer position or by name.
