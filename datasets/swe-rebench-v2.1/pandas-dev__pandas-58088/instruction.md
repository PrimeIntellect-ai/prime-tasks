BUG: No longer can `melt` name the columns for the labels of a `MultiIndex`
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

frame = pd.DataFrame({("A", "a"): range(3), ("A", "b"): range(3, 6)})
frame.melt(var_name=["upper", "lower"])
```


### Issue Description

Running the example gives
```Python traceback
Traceback (most recent call last):
  File "<string>", line 19, in __PYTHON_EL_eval
  File "/home/jdawson/Documents/bugs/pandas-melt/melt_bug.py", line 5, in <module>
    frame.melt(var_name=["upper", "lower"])
  File "/home/jdawson/Documents/bugs/pandas-melt/.venv/lib/python3.12/site-packages/pandas/core/frame.py", line 9839, in melt
    return melt(
           ^^^^^
  File "/home/jdawson/Documents/bugs/pandas-melt/.venv/lib/python3.12/site-packages/pandas/core/reshape/melt.py", line 220, in melt
    raise ValueError(f"{var_name=} must be a scalar.")
ValueError: var_name=['upper', 'lower'] must be a scalar.
```
We can melt the frame if we do not supply `var_name`, but the columns for the labels of the `MultiIndex` will have the abstruse names `variable_0` and `variable_1`.
```Python console
>>> frame.melt()
  variable_0 variable_1  value
0          A          a      0
1          A          a      1
2          A          a      2
3          A          b      3
4          A          b      4
5          A          b      5
```
This bug may be related to #57663.

### Expected Behavior

Versions strictly older than 2.2.0 behave thus.
```Python console
>>> import pandas as pd
>>> frame = pd.DataFrame({("A", "a"): range(3), ("A", "b"): range(3, 6)})
>>> frame
   A
   a  b
0  0  3
1  1  4
2  2  5
>>> frame.melt(var_name=["upper", "lower"])
  upper lower  value
0     A     a      0
1     A     a      1
2     A     a      2
3     A     b      3
4     A     b      4
5     A     b      5
```

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : b552dc95c9fa50e9ca2a0c9f9cdb8757f794fedb
python                : 3.12.2.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 5.15.0-101-generic
Version               : #111~20.04.1-Ubuntu SMP Mon Mar 11 15:44:43 UTC 2024
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : en_GB.UTF-8
LOCALE                : en_GB.UTF-8

pandas                : 3.0.0.dev0+618.gb552dc95c
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : None
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
fastparquet           : None
fsspec                : None
gcsfs                 : None
matplotlib            : None
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
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

</details>
