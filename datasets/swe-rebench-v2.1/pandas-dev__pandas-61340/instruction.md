BUG: df.plot() "Subplots" changes behavior of how values are stacked using the "Stacked" property
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

df = pd.DataFrame([(30, 10, 10), (20, 20, 20), (10, 30, 30)], columns=list('ABC'))
df.plot(kind="bar", stacked=True)
df.plot(subplots= [('A','B')],kind="bar", stacked=True)
plt.show()
print(df)
```

### Issue Description

Using both the "stacked" and "subplots" option when drawing a bar graph changes how the bar graph is stacked.

Illustrated with image below where instead of numberically stacking the values for A and B it just physically overlays them. My guess is it doesn't properly use the "bottom" attribute when drawing B.

![Image](https://github.com/user-attachments/assets/30d4655d-1a88-4321-be17-6ea88bbf2646)

### Expected Behavior

The behavior of the subplot version should be inline with when the option is not used. So the total of the values should equal to A+B for each element

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.11.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.22631
machine               : AMD64
processor             : AMD64 Family 25 Model 33 Stepping 2, AuthenticAMD
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : English_United States.1252

pandas                : 2.2.3
numpy                 : 1.24.2
pytz                  : 2025.1
dateutil              : 2.8.2
pip                   : 25.0
Cython                : None
sphinx                : None
IPython               : 8.12.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.2
lxml.etree            : 5.3.0
matplotlib            : 3.10.0
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : 2.0.9
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2025.1
qtpy                  : None
pyqt5                 : None

</details>
