Unexpected TypeError using `pd.NamedAgg` dict with `pd.rolling`
#### Code Sample

```python

import pandas as pd
animals = pd.DataFrame({'kind': ['cat', 'dog', 'cat', 'dog'],
                        'height': [9.1, 6.0, 9.5, 34.0],
                        'weight': [7.9, 7.5, 9.9, 198.0]})

# (1) - doesn't work
animals.groupby("kind").rolling(1).agg(**{'total weight': pd.NamedAgg(column='weight', aggfunc=sum),
                                          'min_weight': pd.NamedAgg(column='weight', aggfunc=min)})

# (2) - works
animals.groupby("kind").agg(**{'total weight': pd.NamedAgg(column='weight', aggfunc=sum),
                               'min_weight': pd.NamedAgg(column='weight', aggfunc=min)})

# works, but returns multiindex
animals.groupby("kind").rolling(1).agg({'weight': {'total_weight': 'sum', 'min_weight': 'min'}})

# (3) - this is what I'd want, expected output of (1)
animals.groupby("kind").rolling(1).agg({'weight': {'total_weight': 'sum', 'min_weight': 'min'}}).droplevel(0, axis=1)

```
#### Problem description

Pandas version 0.25 provides new aggregate functionality through [NamedAgg](https://pandas-docs.github.io/pandas-docs-travis/whatsnew/v0.25.0.html#groupby-aggregation-with-relabeling). I would expect to be able to pass this in after a groupby as a `pd.apply` statement, and also after a groupby _and_ `pd.rolling`.

However, when I try to pass in a dict of `NamedAgg` tuples as shown in (1) in the example code I get the following TypeError: `TypeError: aggregate() missing 1 required positional argument: 'arg'`

Is this expected or am I incorrectly using this functionality? Thanks in advance!

#### Output of ``pd.show_versions()``

<details>

INSTALLED VERSIONS
------------------
commit           : None
python           : 3.7.4.final.0
python-bits      : 64
OS               : Darwin
OS-release       : 18.7.0
machine          : x86_64
processor        : i386
byteorder        : little
LC_ALL           : None
LANG             : None
LOCALE           : en_US.UTF-8
pandas           : 0.25.1
numpy            : 1.16.1
pytz             : 2018.5
dateutil         : 2.7.3
pip              : 19.1.1
setuptools       : 41.0.1
Cython           : None
pytest           : 4.3.1
hypothesis       : None
sphinx           : 1.8.5
blosc            : None
feather          : None
xlsxwriter       : None
lxml.etree       : None
html5lib         : None
pymysql          : 0.9.2
psycopg2         : 2.7.7 (dt dec pq3 ext lo64)
jinja2           : 2.10.1
IPython          : 7.3.0
pandas_datareader: None
bs4              : 4.7.1
bottleneck       : None
fastparquet      : None
gcsfs            : None
lxml.etree       : None
matplotlib       : 3.0.3
numexpr          : None
odfpy            : None
openpyxl         : 2.6.1
pandas_gbq       : None
pyarrow          : None
pytables         : None
s3fs             : None
scipy            : 1.1.0
sqlalchemy       : 1.3.3
tables           : None
xarray           : None
xlrd             : 1.2.0
xlwt             : None
xlsxwriter       : None

</details>

### Additional contract requirements

- `Rolling.agg` / `Rolling.aggregate` accepts `NamedAgg` specifications supplied as keyword arguments when no positional aggregation function is passed, and the returned `DataFrame` columns are relabeled with the keyword names.
- `Expanding.agg` / `Expanding.aggregate` accepts `NamedAgg` specifications supplied as keyword arguments when no positional aggregation function is passed, and the returned `DataFrame` columns are relabeled with the keyword names.
- `ExponentialMovingWindow.agg` / `ExponentialMovingWindow.aggregate` accepts `NamedAgg` specifications supplied as keyword arguments when no positional aggregation function is passed, and the returned `DataFrame` columns are relabeled with the keyword names.
- The grouped forms `DataFrame.groupby(...).rolling(...).agg(**NamedAgg)`, `DataFrame.groupby(...).expanding(...).agg(**NamedAgg)` and `DataFrame.groupby(...).ewm(...).agg(**NamedAgg)` are supported.
