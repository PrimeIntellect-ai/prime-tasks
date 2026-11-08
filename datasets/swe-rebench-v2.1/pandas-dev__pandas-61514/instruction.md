BUG: to_csv() quotechar/escapechar behavior differs from csv module
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
import csv
import sys

data = [['a', 'b"c', 'def"'], ['a2', None, '"c']]

# no escaping
df = pd.DataFrame(data)
print(df.to_csv(sep='\t', index=False, header=False, quotechar='"', escapechar='\\', quoting=csv.QUOTE_NONE))
print(df.to_csv(sep='\t', index=False, header=False, quotechar='"', escapechar='\\', quoting=csv.QUOTE_NONE, doublequote=False))

# escaping
csv_writer = csv.writer(sys.stdout, delimiter='\t', quotechar='"', escapechar='\\', quoting=csv.QUOTE_NONE)
for r in data:
    _ = csv_writer.writerow(r)
```

### Issue Description

`to_csv()` doesn't escape `quotechar` when `quoting=csv.QUOTE_NONE`.
````
a       b"c     def"
a2              "c
````

### Expected Behavior

`quotechar` gets escaped using `escapechar` even when `quoting=csv.QUOTE_NONE`.
This is the behavior of the csv module.
````
a       b\"c    def\"
a2              \"c
````

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.11.2
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.22621
machine               : AMD64
processor             : Intel64 Family 6 Model 140 Stepping 1, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : English_United States.1252

pandas                : 2.2.3
numpy                 : 1.26.2
pytz                  : 2023.3.post1
dateutil              : 2.8.2
pip                   : 25.0.1
Cython                : None
sphinx                : None
IPython               : 8.24.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
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
openpyxl              : 3.1.5
pandas_gbq            : None
psycopg2              : 2.9.9
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : 2.0.23
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2023.3
qtpy                  : None
pyqt5                 : None

</details>
