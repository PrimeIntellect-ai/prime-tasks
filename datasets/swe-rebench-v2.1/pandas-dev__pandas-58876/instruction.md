BUG: to_datetime behaves differently depending of the format of the string provided
### Pandas version checks

- [ ] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
Python 3.11.7 | packaged by conda-forge | (main, Dec 23 2023, 14:43:09) [GCC 12.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pandas as pd
>>> pd.to_datetime("2016-03-11", dayfirst=True)
Timestamp('2016-11-03 00:00:00')
>>> pd.to_datetime("20160311", dayfirst=True)
Timestamp('2016-03-11 00:00:00')
>>>
```


### Issue Description

Dates of the format "YYYYDDMM" are not converted correctly by to_datetime() when dayfirst=True. to_datetime() still reads the date characters as the months

### Expected Behavior

Python 3.11.7 | packaged by conda-forge | (main, Dec 23 2023, 14:43:09) [GCC 12.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import pandas as pd
>>> pd.to_datetime("2016-03-11", dayfirst=True)
Timestamp('2016-11-03 00:00:00')
>>> pd.to_datetime("20160311", dayfirst=True)
Timestamp('2016-11-03 00:00:00')

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit              : a671b5a8bf5dd13fb19f0e88edc679bc9e15c673
python              : 3.11.7.final.0
python-bits         : 64
OS                  : Linux
OS-release          : 3.10.0-1160.114.2.el7.x86_64
Version             : #1 SMP Sun Mar 3 08:18:39 EST 2024
machine             : x86_64
processor           : x86_64
byteorder           : little
LC_ALL              : None
LANG                : en_US.UTF-8
LOCALE              : en_US.UTF-8

pandas              : 2.1.4
numpy               : 1.26.3
pytz                : 2023.3.post1
dateutil            : 2.8.2
setuptools          : 69.0.3
pip                 : 23.3.2
Cython              : 3.0.7
pytest              : 7.4.4
hypothesis          : 6.94.0
sphinx              : 7.2.6
blosc               : None
feather             : None
xlsxwriter          : 3.1.9
lxml.etree          : 5.1.0
html5lib            : 1.1
pymysql             : None
psycopg2            : None
jinja2              : 3.1.3
IPython             : 8.20.0
pandas_datareader   : None
bs4                 : 4.12.2
bottleneck          : 1.3.7
dataframe-api-compat: None
fastparquet         : 2023.10.1
fsspec              : 2023.12.2
gcsfs               : None
matplotlib          : 3.8.2
numba               : 0.58.1
numexpr             : 2.8.8
odfpy               : None
openpyxl            : 3.1.2
pandas_gbq          : None
pyarrow             : 16.0.0
pyreadstat          : None
pyxlsb              : None
s3fs                : None
scipy               : 1.11.4
sqlalchemy          : 2.0.25
tables              : 3.9.2
tabulate            : 0.9.0
xarray              : 2023.7.0
xlrd                : 2.0.1
zstandard           : 0.19.0
tzdata              : 2023.4
qtpy                : 2.4.1
pyqt5               : None

</details>
