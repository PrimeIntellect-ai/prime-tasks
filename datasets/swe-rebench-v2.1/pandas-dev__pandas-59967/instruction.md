BUG: SparseFrameAccessor.to_dense ignores _constructor
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import scipy.sparse as sp
import pandas as pd

class MF(pd.DataFrame):
    @property
    def _constructor(self):
        return MF

arr = pd.core.arrays.SparseArray.from_spmatrix(sp.csr_matrix((3, 1)))
df = MF(arr)
print(type(df.sparse.to_dense()).__name__)
```


### Issue Description

`to_dense` ignores `_constructor` and always returns `DataFrame`.

```python
    def to_dense(self) -> DataFrame:
        from pandas import DataFrame

        data = {k: v.array.to_dense() for k, v in self._parent.items()}
        [HIDDEN]
```

I think the code should look like this:

```python
    def to_dense(self) -> DataFrame:
        data = {k: v.array.to_dense() for k, v in self._parent.items()}
        [HIDDEN]
```

We use(d) an ugly workaround, but it will stop working in Pandas 3 because of #58733. See our temporary solution in https://github.com/biolab/orange3/pull/6897/commits/98c48e1b3b7c705f10af195a395213114dc2a917. :(

### Expected Behavior

When subclassing `DataFrame` (which, I know, is discouraged, but sometimes difficult to avoid), `to_dense` should observe the constructor returned by `_constructor`.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 23c497bb2f7e05af1fda966e7fb04db942453559
python                : 3.11.10
python-bits           : 64
OS                    : Darwin
OS-release            : 23.6.0
Version               : Darwin Kernel Version 23.6.0: Mon Jul 29 21:14:30 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T6000
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_GB.UTF-8
LOCALE                : en_GB.UTF-8

pandas                : 3.0.0.dev0+1524.g23c497bb2f
numpy                 : 1.26.4
dateutil              : 2.9.0.post0
pip                   : 24.2
Cython                : 3.0.11
sphinx                : 4.5.0
IPython               : 8.27.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.0b2
blosc                 : None
bottleneck            : 1.4.0
fastparquet           : None
fsspec                : None
html5lib              : 1.1
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.4
lxml.etree            : 5.3.0
matplotlib            : 3.9.2
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.5
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : 8.3.3
python-calamine       : None
pytz                  : 2024.2
pyxlsb                : None
s3fs                  : None
scipy                 : 1.15.0.dev0+git20240926.4c936c8
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : 2.0.1
xlsxwriter            : 3.2.0
zstandard             : None
tzdata                : 2024.1
qtpy                  : 2.4.1
pyqt5                 : None

</details>

### Additional contract requirements

- For a DataFrame subclass whose `_constructor` returns that subclass, `to_dense()` should return an instance of that subclass.
