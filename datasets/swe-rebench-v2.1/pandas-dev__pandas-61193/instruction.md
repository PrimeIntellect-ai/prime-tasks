BUG: `DataFrame.pivot` fails with `pyarrow` backend if variable is already encoded as `dictionary`
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd

df = (
    pd.DataFrame([("A", 1), ("B", 2), ("C", 3)], columns=["var", "val"])
    .astype({"var": "string", "val": "float32"})
    .astype({"var": "category", "val": "float32"})
)

# write and reload as parquet with pyarrow backend
df.to_parquet("demo.parquet")
df = pd.read_parquet("demo.parquet", dtype_backend="pyarrow")
print(df.dtypes)  # var is now dictionary[int32,string]

df.pivot(columns=["var"], values=["val"])  # ✘ ArrowNotImplementedError
```


### Issue Description

This bug is caused by https://github.com/apache/arrow/issues/34890: currently, pyarrow's `dictionary_encode` is not idempotent, i.e. it fails with `ArrowNotImplementedError` instead of returning the data as-is if the array is already of dictionary type.

So, either one waits until it is fixed upstream by pyarrow, or [HIDDEN]

### Expected Behavior

Pivot should work with categorical data when using the pyarrow backend.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit           : 37ea63d540fd27274cad6585082c91b1283f963d
python           : 3.11.3.final.0
python-bits      : 64
OS               : Linux
OS-release       : 5.19.0-41-generic
Version          : #42~22.04.1-Ubuntu SMP PREEMPT_DYNAMIC Tue Apr 18 17:40:00 UTC 2
machine          : x86_64
processor        : x86_64
byteorder        : little
LC_ALL           : None
LANG             : en_US.UTF-8
LOCALE           : en_US.UTF-8

pandas           : 2.0.1
numpy            : 1.23.5
pytz             : 2023.3
dateutil         : 2.8.2
setuptools       : 67.7.2
pip              : 23.1.2
Cython           : 0.29.34
pytest           : 7.3.1
hypothesis       : None
sphinx           : 7.0.0
blosc            : None
feather          : None
xlsxwriter       : None
lxml.etree       : 4.9.2
html5lib         : None
pymysql          : 1.0.3
psycopg2         : None
jinja2           : 3.1.2
IPython          : 8.13.1
pandas_datareader: None
bs4              : 4.12.2
bottleneck       : None
brotli           : None
fastparquet      : 2023.4.0
fsspec           : 2023.4.0
gcsfs            : None
matplotlib       : 3.7.1
numba            : 0.57.0rc1
numexpr          : 2.8.4
odfpy            : None
openpyxl         : 3.1.2
pandas_gbq       : None
pyarrow          : 11.0.0
pyreadstat       : None
pyxlsb           : None
s3fs             : None
scipy            : 1.10.1
snappy           : None
sqlalchemy       : 1.4.48
tables           : 3.8.0
tabulate         : 0.9.0
xarray           : 2023.4.2
xlrd             : None
zstandard        : None
tzdata           : 2023.3
qtpy             : None
pyqt5            : None

</details>
