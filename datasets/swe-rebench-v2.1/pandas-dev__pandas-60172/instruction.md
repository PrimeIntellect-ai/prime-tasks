BUG: Frequency shift on empty DataFrame doesn't shift index
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
dates = pd.date_range('2020-01-01', '2020-01-03')
df = pd.DataFrame(index=dates, columns=[])
day = pd.offsets.Day()
shifted_dates = df.shift(freq=day).index
assert (shifted_dates == dates + day).all()
```


### Issue Description

Running `DataFrame.shift` with `freq` on a `DataFrame` with empty columns does not shift the index.

### Expected Behavior

I would expect `DataFrame.shift` to shift the index similarly to how it would if the `DataFrame` had columns.  Particularly with the above example, I would expect `df.reindex(['A'], axis=1).shift(freq=day).reindex([], axis=1)` to be equivalent to `df.shift(freq=day)`.

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit           : 91111fd99898d9dcaa6bf6bedb662db4108da6e6
python           : 3.10.13.final.0
python-bits      : 64
OS               : Linux
OS-release       : 5.15.102.hrtdev
Version          : #1 SMP Tue Mar 14 13:23:09 EDT 2023
machine          : x86_64
processor        :
byteorder        : little
LC_ALL           :
LANG             : en_US.UTF-8
LOCALE           : en_US.UTF-8

pandas           : 1.5.1
numpy            : 1.23.2
pytz             : 2022.1
dateutil         : 2.8.2
setuptools       : 62.1.0
pip              : 24.2
Cython           : 0.29.30
pytest           : 8.2.1
hypothesis       : 6.108.2
sphinx           : 5.0.2
blosc            : 1.10.6
feather          : None
xlsxwriter       : None
lxml.etree       : 4.9.1
html5lib         : 1.1
pymysql          : 1.0.2
psycopg2         : 2.9.3
jinja2           : 3.1.2
IPython          : 8.10.0
pandas_datareader: None
bs4              : 4.11.1
bottleneck       : 1.3.5
brotli           : 1.0.9
fastparquet      : 0.8.1
fsspec           : 2023.10.0
gcsfs            : None
matplotlib       : 3.5.2+hrt1
numba            : 0.59.0
numexpr          : 2.8.3
odfpy            : None
openpyxl         : 3.0.10
pandas_gbq       : None
pyarrow          : 12.2.2.dev14+g99c7fc95e
pyreadstat       : None
pyxlsb           : 1.0.9
s3fs             : None
scipy            : 1.9.1
snappy           : None
sqlalchemy       : 1.4.49
tables           : 3.7.0
tabulate         : 0.8.10
xarray           : 2022.6.0
xlrd             : 2.0.1
xlwt             : None
zstandard        : 0.20.0
tzdata           : 2022.1

</details>
