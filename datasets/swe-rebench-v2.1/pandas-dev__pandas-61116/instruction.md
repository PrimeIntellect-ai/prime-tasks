PERF: Surprisingly slow nlargest with duplicates in the index
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this issue exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this issue exists on the main branch of pandas.


### Reproducible Example

```
N = 1500
slow_df = pd.DataFrame({'a': np.arange(N)}, index=[pd.NA] * N)
%timeit slow_df['a'].nlargest()

fast_df = pd.DataFrame({'a': np.arange(N)})
%timeit fast_df['a'].nlargest()
```
results in
```
448 ms ± 9.63 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)
105 µs ± 850 ns per loop (mean ± std. dev. of 7 runs, 10,000 loops each)
```
so 4000 times slower with a non unique index.  This was very surprising.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit              : e86ed377639948c64c429059127bcf5b359ab6be
python              : 3.11.5.final.0
python-bits         : 64
OS                  : Darwin
OS-release          : 20.6.0
Version             : Darwin Kernel Version 20.6.0: Fri Dec 16 00:34:59 PST 2022; root:xnu-7195.141.49~1/RELEASE_ARM64_T8101
machine             : arm64
processor           : arm
byteorder           : little
LC_ALL              : None
LANG                : en_US.UTF-8
LOCALE              : en_US.UTF-8

pandas              : 2.1.1
numpy               : 1.26.0
pytz                : 2023.3.post1
dateutil            : 2.8.2
setuptools          : 68.0.0
pip                 : 23.2.1
Cython              : None
pytest              : 7.4.2
hypothesis          : None
sphinx              : 7.2.6
blosc               : None
feather             : None
xlsxwriter          : None
lxml.etree          : None
html5lib            : None
pymysql             : None
psycopg2            : None
jinja2              : 3.1.2
IPython             : 8.16.1
pandas_datareader   : None
bs4                 : 4.12.2
bottleneck          : None
dataframe-api-compat: None
fastparquet         : None
fsspec              : None
gcsfs               : None
matplotlib          : 3.8.0
numba               : None
numexpr             : None
odfpy               : None
openpyxl            : 3.1.2
pandas_gbq          : None
pyarrow             : 11.0.0
pyreadstat          : None
pyxlsb              : None
s3fs                : None
scipy               : 1.11.3
sqlalchemy          : None
tables              : None
tabulate            : None
xarray              : None
xlrd                : None
zstandard           : None
tzdata              : 2023.3
qtpy                : None
pyqt5               : None

</details>


### Prior Performance

_No response_

### Additional contract requirements

- `Series.nlargest` and `Series.nsmallest` must not slow down super-linearly when the index contains many duplicate values. When every index label is the same, the runtime should grow roughly linearly with the length of the Series, not quadratically: quadrupling the length should not multiply the runtime by anything close to sixteen.
- The selected values and their original index labels must be unchanged by this optimization.
