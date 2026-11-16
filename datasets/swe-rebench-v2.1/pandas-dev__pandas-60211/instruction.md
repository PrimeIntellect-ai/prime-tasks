BUG: stacked bar graphs show invalid label position due to invalid rectangle bottom when data is 0
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
import matplotlib.pyplot as plt
permutations = [(a,b,c) for a in range(2) for b in range(2) for c in range(3)]
data = [
    {'i': i, 'a':a, 'b':b, 'c':c, 't': a+b+c}
    for i, (a,b,c) in enumerate(permutations)
]
df = pd.DataFrame.from_dict(data)
ax = df[['a','b', 'c']].plot.bar(stacked=True)
bl = ax.bar_label(ax.containers[-1], df['t'])
plt.show()
```


### Issue Description

if the top part of the stacked plot has data value 0, the bar-label does not appear on top, but at the bottom of the bar.
![grafik](https://github.com/user-attachments/assets/2c839adf-44e6-445e-bba5-0af33eef04af)

Further debugging shows that all bars with data = 0 have their y position set to 0.0. They should have the top of the bar below as their bottom = y.

### Expected Behavior

Bar-Labels should be positioned on top for all stacks.

![grafik](https://github.com/user-attachments/assets/58c5bc3d-1e21-41bc-8804-f2f5516ae593)

this behaviour can be produced by correcting the y positions of the defective bars

[HIDDEN]


### Installed Versions

INSTALLED VERSIONS
------------------
commit                : d9cdd2ee5a58015ef6f4d15c7226110c9aab8140
python                : 3.11.9.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.22631
machine               : AMD64
processor             : Intel64 Family 6 Model 186 Stepping 2, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : de_DE.cp1252

pandas                : 2.2.2
numpy                 : 2.0.1
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 65.5.0
pip                   : 24.2
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
jinja2                : 3.1.4
IPython               : 8.26.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
gcsfs                 : None
matplotlib            : 3.9.1
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
scipy                 : 1.14.0
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None

### Additional contract requirements

- In stacked bar plots, when the top segment has value zero, its label must be positioned at the cumulative top of the stack, rather than at the base of the bar.
